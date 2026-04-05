import Foundation

public actor OrchestratorRuntime {
    private let planner: PlannerAgent
    private let memory: MemoryAgent
    private let cloudProvider: CloudProvider
    private let localProvider: MLXProvider?
    private let bridgeProvider: BridgeProvider?
    private let toolRegistry: ToolRegistry
    private let bus: SignalBus
    private let vaultManager: VaultManager
    
    private var onStepUpdate: (@Sendable (TaskStep) -> Void)?
    private var onChatMessage: (@Sendable (ChatMessage) -> Void)?
    private var onStatusUpdate: (@Sendable (AgentStatus) -> Void)?
    private var onTokenUpdate: (@Sendable (TokenCount, Decimal) -> Void)?
    
    private var turnsWithoutProgress = 0
    private let MAX_TURNS_WITHOUT_PROGRESS = 5
    private var isInterrupted = false
    private var lastThought = ""
    private var thoughtRepetitionCount = 0
    private var activeContextManager: DynamicContextManager?
    private var sourcesAnalyzed = 0
    
    public init(
        planner: PlannerAgent,
        memory: MemoryAgent,
        cloudProvider: CloudProvider,
        localProvider: MLXProvider?,
        bridgeProvider: BridgeProvider?,
        toolRegistry: ToolRegistry,
        bus: SignalBus,
        vaultManager: VaultManager
    ) {
        self.planner = planner
        self.memory = memory
        self.cloudProvider = cloudProvider
        self.localProvider = localProvider
        self.bridgeProvider = bridgeProvider
        self.toolRegistry = toolRegistry
        self.bus = bus
        self.vaultManager = vaultManager
        
        NotificationCenter.default.addObserver(forName: NSNotification.Name("RetryParse"), object: nil, queue: .main) { [weak self] _ in
            Task {
                await self?.handleRetryParse()
            }
        }
    }
    
    private func handleRetryParse() async {
        AgentLogger.logAudit(level: .warn, agent: "Orchestrator", message: "User requested a re-parse. Prompting model for valid JSON.")
        let retryMsg = "Observation: JSON parse failed. Please provide the research report again in a simpler, valid JSON format. Ensure all quotes are escaped and the structure matches the schema."
        await activeContextManager?.addMessage(Message(role: "user", content: retryMsg))
    }
    
    public func setStepUpdateHandler(_ handler: @escaping @Sendable (TaskStep) -> Void) {
        self.onStepUpdate = handler
    }
    
    public func setChatMessageUpdateHandler(_ handler: @escaping @Sendable (ChatMessage) -> Void) {
        self.onChatMessage = handler
    }
    
    public func setStatusUpdateHandler(_ handler: @escaping @Sendable (AgentStatus) -> Void) {
        self.onStatusUpdate = handler
    }
    public func setTokenUpdateHandler(_ handler: @escaping @Sendable (TokenCount, Decimal) -> Void) { self.onTokenUpdate = handler }
    
    public func interrupt() {
        self.isInterrupted = true
    }
    
    public func executeTask(prompt: String, session: Session, complexity: Int, forceProviders: [ProviderID]? = nil, config: InferenceConfig) async throws {
        self.onStatusUpdate?(.working)
        self.isInterrupted = false
        
        let contextManager = DynamicContextManager(maxTokens: 8000, provider: cloudProvider)
        self.activeContextManager = contextManager
        self.sourcesAnalyzed = 0 
        await contextManager.addMessage(Message(role: "user", content: prompt))
        
        let startTime = Date()
        let isResearch = prompt.lowercased().contains(any: ["araştır", "incele", "analiz et", "rapor oluştur", "karşılaştır"])
        
        let progressTask = Task {
            var stepCounter = 1
            while !Task.isCancelled {
                // v9.4: Increased interval from 30s to 60s to reduce UI clutter
                try? await Task.sleep(nanoseconds: 60_000_000_000)
                let elapsed = Int(Date().timeIntervalSince(startTime))
                
                let emoji = isResearch ? (stepCounter % 2 == 0 ? "📡" : "🔍") : "⚙️"
                let progressMsg = isResearch ? 
                    "\(emoji) Analiz edilen kaynak: \(self.sourcesAnalyzed)... Veriler işleniyor (\(elapsed)s)" :
                    "⚙️ İşleniyor: Adım \(stepCounter) devam ediyor... (\(elapsed)s)"
                
                self.onChatMessage?(ChatMessage(role: .assistant, content: progressMsg))
                
                let step = TaskStep(name: " İlerleme...", status: "Çalışıyor", latency: "\(elapsed)s", thought: progressMsg)
                self.onStepUpdate?(step)
                stepCounter += 1
            }
        }
        
        defer { progressTask.cancel() }
        
        do {
            for turn in 1...50 {
                if isInterrupted {
                    AgentLogger.logAudit(level: .info, agent: "Orchestrator", message: "Task interrupted by user.")
                    await session.setFinalAnswer("İşlem kullanıcı tarafından durduruldu.")
                    break
                }
                
                AgentLogger.logAudit(level: .info, agent: "Orchestrator", message: "Turn \(turn)")
                
                let history = await contextManager.getMessages()
                let systemPrompt = SystemPrompts.orchestrator(tools: toolRegistry.listTools())
                
                let request = CompletionRequest(
                    taskID: UUID().uuidString,
                    systemPrompt: systemPrompt,
                    messages: history,
                    maxTokens: 3000,
                    sensitivityLevel: .public,
                    complexity: complexity
                )
                
                let provider = try resolveProvider(force: forceProviders, config: config)
                
                var response: CompletionResponse?
                var retryCount = 0
                let maxRetries = 2
                
                while retryCount <= maxRetries {
                    do {
                        response = try await provider.complete(request)
                        break
                    } catch ProviderError.emptyResponse {
                        retryCount += 1
                        if retryCount <= maxRetries {
                            AgentLogger.logAudit(level: .warn, agent: "Orchestrator", message: "Empty response from provider, retrying (\(retryCount)/\(maxRetries))...")
                            try await Task.sleep(nanoseconds: 1_000_000_000 * UInt64(retryCount))
                            continue
                        } else {
                            AgentLogger.logAudit(level: .error, agent: "Orchestrator", message: "Empty response persisted. Forcing completion.")
                            let forcedPrompt = "Observation: Empty response received. Please provide your answer or call tools."
                            await contextManager.addMessage(Message(role: "user", content: forcedPrompt))
                            response = nil 
                            break
                        }
                    } catch { throw error }
                }
                
                guard let finalResponse = response else { continue }
                
                // v9.6: Inference Integrity Check (Async Post-Inference)
                let validation = InferenceValidator.validate(finalResponse.content, format: .plainText)
                if !validation.isValid {
                    AgentLogger.logAudit(level: .warn, agent: "Orchestrator", message: "Inference Integrity Check Failed: \(validation.reason ?? "Unknown"). Retrying...")
                    
                    // Trigger Recovery (Non-blocking)
                    let metrics = await LocalModelWatchdog.shared.metrics
                    Task { @MainActor in
                        await AutoRecoveryEngine.shared.attemptFix(metrics)
                    }
                    
                    if retryCount < maxRetries {
                        retryCount += 1
                        continue
                    }
                }
                self.onTokenUpdate?(finalResponse.tokensUsed, finalResponse.costUSD)
                
                let sanitizedContent = finalResponse.content
                await contextManager.addMessage(Message(role: "assistant", content: sanitizedContent))
                
                var toolBlocks: [ToolCall] = finalResponse.toolCalls ?? []
                let textBlocks = ThinkParser.parse(sanitizedContent)
                
                // v9.4: Stall Detection (3 Turns)
                let currentThought = finalResponse.thinkBlock ?? sanitizedContent
                if currentThought == lastThought {
                    thoughtRepetitionCount += 1
                } else {
                    lastThought = currentThought
                    thoughtRepetitionCount = 0
                }

                let stallThreshold = UserDefaults.standard.integer(forKey: "stallThreshold") > 0 
                    ? UserDefaults.standard.integer(forKey: "stallThreshold") 
                    : 3
                
                if thoughtRepetitionCount >= stallThreshold {
                    AgentLogger.logAudit(level: .warn, agent: "Orchestrator", message: "Stall detected (Turn \(turn)). Terminating to prevent loop.")
                    await session.setFinalAnswer("⚠️ İşlem döngüye girdiği için durduruldu. Lütfen komutu daha açık şekilde tekrar verin veya sistem izinlerini kontrol edin.")
                    break
                }
                
                var foundFinalAnswer = false
                var finalAnswerText = ""
                
                for block in textBlocks {
                    if let tool = block.toolCall {
                        toolBlocks.append(tool)
                    } else if !block.thought.isEmpty {
                        // v9.4: Refined termination logic for simple tool results
                        let isReportLike = block.thought.contains(any: ["# Araştırma Raporu", "Analiz Sonuçları", "Bulgular", "Research Report"])
                        let noToolsCalled = toolBlocks.isEmpty && (finalResponse.toolCalls?.isEmpty ?? true)
                        
                        if noToolsCalled && !sanitizedContent.contains("```tool_code") {
                            // If just text output and no tool was requested in this turn
                            if !isResearch || isReportLike || turn > 15 {
                                foundFinalAnswer = true
                                finalAnswerText = block.thought
                            }
                        }
                    }
                }
                
                if let think = finalResponse.thinkBlock, !think.isEmpty {
                    let step = TaskStep(name: "Thinking...", status: "Analysis", latency: "\(finalResponse.latencyMs)ms", thought: think)
                    self.onStepUpdate?(step)
                }
                
                // v9.8: Intent-aware search forcing to prevent apology loops & Research Report priority fix
                if turn == 1 && isResearch && toolBlocks.isEmpty {
                    let hasSearchIntent = sanitizedContent.lowercased().contains(any: ["google", "safari", "arama", "search", "araştır", "bakayım", "bulayım", "inceleyim", "analiz edeyim"])
                    let isMusicRequest = sanitizedContent.lowercased().contains(any: ["müzik", "çal", "play", "sezen", "music", "apple music"])
                    
                    if !hasSearchIntent && !isMusicRequest {
                        AgentLogger.logAudit(level: .info, agent: "Orchestrator", message: "No tools and no intent on Turn 1. Forcing search tools.")
                        await contextManager.addMessage(Message(role: "user", content: "Observation: Lütfen araştırmaya başlamak için önce 'google_search' veya 'safari_automation' araçlarını kullanın. Sadece metinle cevap vermeyiniz."))
                        continue
                    }
                }
                
                if toolBlocks.isEmpty {
                    turnsWithoutProgress += 1
                    if turnsWithoutProgress >= MAX_TURNS_WITHOUT_PROGRESS {
                        await session.setFinalAnswer("Üzgünüm, araştırmada ilerleme kaydedemedim.")
                        break
                    }
                } else {
                    turnsWithoutProgress = 0
                    for toolCall in toolBlocks {
                        AgentLogger.logAudit(level: .info, agent: "Orchestrator", message: "Executing \(toolCall.tool)")
                        
                        let status = self.toolRegistry.getToolStatus(named: toolCall.tool)
                        let isEnabled = config.enabledTools[toolCall.tool] ?? true
                        
                        guard isEnabled && status.isAvailable else {
                            let obs = "Observation: Error - Tool '\(toolCall.tool)' is currently unavailable."
                            await contextManager.addMessage(Message(role: "user", content: obs))
                            continue
                        }
                        
                        // Tool Timeout (60s)
                        do {
                            let observation = try await withThrowingTaskGroup(of: String.self) { group in
                                group.addTask { try await self.toolRegistry.execute(toolCall: toolCall, session: session) }
                                group.addTask {
                                    try await Task.sleep(nanoseconds: 60_000_000_000)
                                    throw ToolError.executionError("Timeout (60s)")
                                }
                                guard let result = try await group.next() else { throw ToolError.executionError("No result") }
                                group.cancelAll()
                                return result
                            }
                            
                            if ["google_search", "web_search", "safari_automation", "web_fetch"].contains(toolCall.tool) {
                                self.sourcesAnalyzed += 1
                            }
                            await contextManager.addMessage(Message(role: "user", content: "Observation: \(observation)"))
                        } catch {
                            await contextManager.addMessage(Message(role: "user", content: "Observation: Error - \(error.localizedDescription)"))
                        }
                    }
                }
                
                if foundFinalAnswer {
                    await session.setFinalAnswer(finalAnswerText)
                    break
                }
            }
        } catch {
            await session.setFinalAnswer("⚠️ Kritik hata: \(error.localizedDescription)")
        }
        self.onStatusUpdate?(.idle)
    }
    
    private func resolveProvider(force: [ProviderID]?, config: InferenceConfig) throws -> any LLMProvider {
        if let force = force?.first {
            if force == .mlx, let p = localProvider { return p }
            if force == .openrouter { return cloudProvider }
            if force == .bridge, let p = bridgeProvider { return p }
        }
        for pid in config.providerPriority {
            if pid == .mlx, let p = localProvider { return p }
            if pid == .openrouter { return cloudProvider }
            if pid == .bridge, let p = bridgeProvider { return p }
        }
        throw InferenceError.localProviderUnavailable("No provider found.")
    }
}

fileprivate extension String {
    func contains(any substrings: [String]) -> Bool {
        for s in substrings {
            if self.contains(s) { return true }
        }
        return false
    }
}
