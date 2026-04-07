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
    private var sessionContext: SessionContext
    
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
    private var currentAction = "İşleniyor..." // v10.1: Real-time action tracking
    
    private var isResearchModeActive = false
    
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
        self.sessionContext = SessionContext() // Initialized with defaults
        
        // v9.9.13: Parallel Notification Listening (AsyncSequence)
        Task { [weak self] in
            for await _ in NotificationCenter.default.notifications(named: NSNotification.Name("RetryParse")) {
                await self?.handleRetryParse()
            }
        }
        
        Task { [weak self] in
            for await note in NotificationCenter.default.notifications(named: .activeProviderChanged) {
                if let model = note.userInfo?["model"] as? ModelSource {
                    await self?.updateSessionModel(from: model)
                }
            }
        }
    }
    
    private func updateSessionModel(from source: ModelSource) async {
        let providerID: ProviderID
        switch source {
        case .localMLX: providerID = .mlx
        case .openRouter: providerID = .openrouter
        case .bridge: providerID = .bridge
        case .custom(let pid, _, _, _, _): providerID = ProviderID(rawValue: pid) ?? .mlx
        }
        self.sessionContext.updateModel(providerID)
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
        
        // v9.9.11: Universal Intent Detection (Action + Research)
        let researchKeywords = ["araştır", "research", "deep analysis", "rapor oluştur", "incele", "analiz et"]
        let actionKeywords = ["aç", "çal", "yaz", "oku", "sil", "bul", "analiz et", "göster", "çalıştır", "play", "open", "music", "safari"]
        
        self.isResearchModeActive = researchKeywords.contains { prompt.lowercased().contains($0) }
        let isActionRequested = actionKeywords.contains { prompt.lowercased().contains($0) }
        
        AgentLogger.logAudit(level: .info, agent: "Orchestrator", message: "Mode: \(isResearchModeActive ? "RESEARCH" : "CHAT") | Action: \(isActionRequested)")
        
        let contextManager = DynamicContextManager(maxTokens: 8000, provider: cloudProvider)
        self.activeContextManager = contextManager
        self.sourcesAnalyzed = 0 
        await contextManager.addMessage(Message(role: "user", content: prompt))
        
        let startTime = Date()
        
        let progressTask = Task {
            var stepCounter = 1
            while !Task.isCancelled {
                let interval = await self.calculateHeartbeatInterval()
                try? await Task.sleep(nanoseconds: interval * 1_000_000_000)
                
                let elapsed = Int(Date().timeIntervalSince(startTime))
                let emoji = isResearchModeActive ? (stepCounter % 2 == 0 ? "📡" : "🔍") : "⚙️"
                
                let progressMsg = isResearchModeActive ? 
                    "\(emoji) Analiz edilen kaynak: \(self.sourcesAnalyzed)... (\(elapsed)s)" :
                    "⚙️ \(self.currentAction) (\(elapsed)s)"
                
                self.onChatMessage?(ChatMessage(role: .assistant, content: progressMsg, isStatus: true))
                
                let step = TaskStep(name: "KAIROS Heartbeat", status: "Active", latency: "\(elapsed)s", thought: progressMsg)
                self.onStepUpdate?(step)
                stepCounter += 1
            }
        }
        
        defer { 
            progressTask.cancel() 
            Task {
                await TulparActor.shared.recordEvent(.taskCompleted(success: true)) // Simplification
                await DreamActor.shared.consolidateIfNeeded(memoryAgent: self.memory, cloudProvider: self.cloudProvider)
            }
        }
        
        // v10.0: Signal Task Start
        await TulparActor.shared.recordEvent(.taskStarted)
        
        do {
            for turn in 1...50 {
                if isInterrupted {
                    AgentLogger.logAudit(level: .info, agent: "Orchestrator", message: "Task interrupted by user.")
                    await session.setFinalAnswer("İşlem kullanıcı tarafından durduruldu.")
                    break
                }
                
                // v10.0: Token Budget Guard
                let approved = await TokenBudgetActor.shared.requestApproval(estimatedTokens: 1000)
                if !approved {
                    await session.setFinalAnswer("⚠️ Bütçe veya termal limitler nedeniyle işlem durduruldu.")
                    break
                }
                
                let provider = try resolveProvider(force: forceProviders, config: config)
                let history = await contextManager.getMessages()
                
                // v9.9.15: Local TTFT Optimization (Pruning)
                if provider.providerID == .mlx || provider.providerID == .bridge {
                    await contextManager.trimMessages(limit: 10)
                }
                
                // v9.9.11: Universal Tool Awareness Logic
                let allTools = toolRegistry.listTools()
                let systemPrompt = isResearchModeActive ? 
                    SystemPrompts.orchestrator(tools: allTools) : 
                    SystemPrompts.chat(tools: allTools)
                
                let request = CompletionRequest(
                    taskID: UUID().uuidString,
                    systemPrompt: systemPrompt,
                    messages: history,
                    maxTokens: 3000,
                    sensitivityLevel: .public,
                    complexity: complexity
                )
                
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
                
                // v10.0: Token Accounting (Async/Await compliant)
                await TokenBudgetActor.shared.recordUsage(tokens: finalResponse.tokensUsed.total, cost: finalResponse.costUSD)
                await TokenAccountant.shared.record(
                    input: finalResponse.tokensUsed.prompt,
                    output: finalResponse.tokensUsed.completion,
                    cached: finalResponse.tokensUsed.cached
                )
                
                let guardConfig = TokenGuardConfig.shared
                let sanitizedContent = OutputSchemaGuard.sanitize(
                    finalResponse.content, 
                    inputTokens: finalResponse.tokensUsed.prompt, 
                    config: guardConfig
                )
                
                // v10.0: BriefMode Formatting handled via OutputSchemaGuard.sanitize
                let displayContent = sanitizedContent
                
                await contextManager.addMessage(Message(role: "assistant", content: sanitizedContent))
                self.onChatMessage?(ChatMessage(role: .assistant, content: displayContent))
                
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
                        let isReportLike = block.thought.containsAny(["# Araştırma Raporu", "Analiz Sonuçları", "Bulgular", "Research Report"])
                        let noToolsCalled = toolBlocks.isEmpty && (finalResponse.toolCalls?.isEmpty ?? true)
                        
                        if noToolsCalled && !sanitizedContent.contains("```tool_code") {
                            // If just text output and no tool was requested in this turn
                            if !isResearchModeActive || isReportLike || turn > 15 {
                                foundFinalAnswer = true
                                finalAnswerText = block.thought
                            }
                        }
                    }
                }
                
                if let think = finalResponse.thinkBlock, !think.isEmpty {
                    AgentLogger.logAudit(level: .info, agent: "Orchestrator", message: "🧠 [THOUGHT] \(think)")
                    let step = TaskStep(name: "Thinking...", status: "Analysis", latency: "\(finalResponse.latencyMs)ms", thought: think)
                    self.onStepUpdate?(step)
                } else {
                    AgentLogger.logAudit(level: .info, agent: "Orchestrator", message: "📝 [RESPONSE] \(sanitizedContent)")
                }
                
                // v9.9.13: Universal Intent Alignment & Autonomous Choice Guardrails
                if turn == 1 && isResearchModeActive && toolBlocks.isEmpty {
                    AgentLogger.logAudit(level: .warn, agent: "Orchestrator", message: "⚠️ [AUTONOMOUS NUDGE] No tools called on Turn 1. Forcing tool usage for \(provider.providerID).")
                    let nudge = "Observation: Lütfen araştırmaya başlamak için önce uygun araçları (google_search, safari_automation, doceye vb.) kullanın. Modelinizden doğrudan cevap beklemiyorum; önce veri toplamanız gerekmektedir. Hangi aracı kullanacağınıza siz karar verin."
                    await contextManager.addMessage(Message(role: "user", content: nudge))
                    continue
                }
                
                // v9.9.13: Mid-loop Nudge for Stall Prevention
                if isResearchModeActive && toolBlocks.isEmpty && turn > 1 && !foundFinalAnswer {
                    turnsWithoutProgress += 1
                    if turnsWithoutProgress >= 2 {
                        AgentLogger.logAudit(level: .warn, agent: "Orchestrator", message: "⚠️ [STALL NUDGE] No tools called for 2 turns. Reminding model of its capabilities.")
                        let nudge = "Observation: Hala araştırma aşamasındasınız. Lütfen elinizdeki araçları kullanarak derinlemesine inceleme yapın veya raporu finalize edin. Boş cevap vermeyiniz."
                        await contextManager.addMessage(Message(role: "user", content: nudge))
                        turnsWithoutProgress = 0 // Reset after nudge
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
                        self.currentAction = "\(toolCall.tool) çalıştırılıyor..."
                        AgentLogger.logAudit(level: .info, agent: "Orchestrator", message: "🛠 [TOOL CALL] \(toolCall.tool) with params: \(toolCall.params)")
                        
                        let status = self.toolRegistry.getToolStatus(named: toolCall.tool)
                        let isEnabled = config.enabledTools[toolCall.tool] ?? true
                        
                        guard isEnabled && status.isAvailable else {
                            AgentLogger.logAudit(level: .warn, agent: "Orchestrator", message: "❌ [TOOL ERROR] Tool \(toolCall.tool) is disabled or unavailable")
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
                            
                            AgentLogger.logAudit(level: .info, agent: "Orchestrator", message: "📡 [OBSERVATION] \(toolCall.tool) returned \(observation.count) characters. Snippet: \(String(observation.prefix(200)))...")
                            
                            if ["google_search", "web_search", "safari_automation", "web_fetch"].contains(toolCall.tool) {
                                self.sourcesAnalyzed += 1
                            }
                            await contextManager.addMessage(Message(role: "user", content: "Observation: \(observation)"))
                        } catch {
                            AgentLogger.logAudit(level: .error, agent: "Orchestrator", message: "❌ [TOOL ERROR] \(toolCall.tool) failed: \(error.localizedDescription)")
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
        // v9.9.13: Respect Model Persistence from SessionContext
        let preferredModel = sessionContext.selectedModel
        
        if let force = force?.first {
            if force == .mlx, let p = localProvider { return p }
            if force == .openrouter { return cloudProvider }
            if force == .bridge, let p = bridgeProvider { return p }
        }
        
        // Priority 1: Sticky Session Model
        if preferredModel == .mlx, let p = localProvider { return p }
        if preferredModel == .openrouter { return cloudProvider }
        
        // Priority 2: Config Priority
        for pid in config.providerPriority {
            if pid == .mlx, let p = localProvider { return p }
            if pid == .openrouter { return cloudProvider }
            if pid == .bridge, let p = bridgeProvider { return p }
        }
        
        // v10.1: Enforcement - If local requested but failed, don't silent fallback
        if config.strictLocal {
             throw InferenceError.localProviderUnavailable("Yerel model (Titan) şu an hazır değil. Lütfen ayarları kontrol edin.")
        }

        throw InferenceError.localProviderUnavailable("No provider found.")
    }
    
    private func calculateHeartbeatInterval() async -> UInt64 {
        let thermal = ProcessInfo.processInfo.thermalState
        // v10.0 KAIROS: Adaptive Heartbeat
        switch thermal {
        case .serious, .critical: return 15
        case .fair, .nominal: return 60
        @unknown default: return 30
        }
    }
}

/// Helper to format content for BriefMode (Bullet points only)
public struct BriefFormatter {
    public static func format(_ content: String) -> String {
        let lines = content.components(separatedBy: .newlines)
        let bulletLines = lines.filter { 
            let t = $0.trimmingCharacters(in: .whitespacesAndNewlines)
            return t.hasPrefix("-") || t.hasPrefix("*") || t.hasPrefix("•") 
        }
        
        if bulletLines.isEmpty {
            // Fallback: Take first two sentences
            let sentences = content.components(separatedBy: ". ")
            return sentences.prefix(2).joined(separator: ". ") + "..."
        }
        
        return bulletLines.joined(separator: "\n")
    }
}

fileprivate extension String {
    func containsAny(_ substrings: [String]) -> Bool {
        for s in substrings {
            if self.contains(s) { return true }
        }
        return false
    }
}
