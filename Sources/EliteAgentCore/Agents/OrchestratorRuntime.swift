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
    
    // Phase 1: Progressive loop control (v8.5)
    private var turnsWithoutProgress = 0
    private let MAX_TURNS_WITHOUT_PROGRESS = 5
    private let TOOL_TIMEOUT_NANOSECONDS: UInt64 = 300_000_000_000 // 300s (5 minutes)
    private var isInterrupted = false
    
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
        await contextManager.addMessage(Message(role: "user", content: prompt))
        
        // Progress Feedback Timer (30s)
        let startTime = Date()
        let isResearch = prompt.lowercased().contains(any: ["araştır", "incele", "analiz et", "rapor oluştur", "karşılaştır"])
        
        let progressTask = Task {
            var stepCounter = 1
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 30_000_000_000)
                let elapsed = Int(Date().timeIntervalSince(startTime))
                
                let emoji = isResearch ? (stepCounter % 2 == 0 ? "📡" : "🔍") : "⚙️"
                let progressMsg = isResearch ? 
                    "\(emoji) \(stepCounter)/10 kaynak tarandı: Veriler analiz ediliyor... (\(elapsed)s)" :
                    "⚙️ İşleniyor: Adım \(stepCounter) devam ediyor... (\(elapsed)s)"
                
                self.onChatMessage?(ChatMessage(role: .assistant, content: progressMsg))
                
                let step = TaskStep(name: " İlerleme...", status: "Çalışıyor", latency: "\(elapsed)s", thought: progressMsg)
                self.onStepUpdate?(step)
                stepCounter += 1
            }
        }
        
        defer { progressTask.cancel() }
        
        var lastToolCallJSON: String? = nil
        var duplicateCount = 0
        
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
                maxTokens: 3000, // Increased for research mode
                sensitivityLevel: .public,
                complexity: complexity
            )
            
            let provider = try resolveProvider(force: forceProviders, config: config)
            let response = try await provider.complete(request)
            
            self.onTokenUpdate?(response.tokensUsed, response.costUSD)
            
            // Phase 1: Deduplicate history entries (v8.5)
            let sanitizedContent = response.content
            await contextManager.addMessage(Message(role: "assistant", content: sanitizedContent))
            
            let parsedBlocks = ThinkParser.parse(sanitizedContent)
            
            var toolBlocks: [ToolCall] = []
            var foundFinalAnswer = false
            var finalAnswerText = ""
            
            for block in parsedBlocks {
                if let tool = block.toolCall {
                    toolBlocks.append(tool)
                } else if !block.thought.isEmpty {
                    // Logic for Final Answer detection: If it's a non-tool block and not just a think block
                    if !sanitizedContent.contains("```tool_code") {
                        foundFinalAnswer = true
                        finalAnswerText = block.thought
                    }
                }
            }
            
            // Mandatory Tool Trigger for Research (v8.6)
            if turn == 1 && isResearch && toolBlocks.isEmpty {
                AgentLogger.logAudit(level: .info, agent: "Orchestrator", message: "Research intent detected. Forcing search tools.")
                await contextManager.addMessage(Message(role: "user", content: "Observation: Lütfen araştırmaya başlamak için önce 'google_search' veya 'safari_automation' araçlarını kullanın. Henüz somut veri taranmadı."))
                continue
            }
            
            if toolBlocks.isEmpty {
                turnsWithoutProgress += 1
                if turnsWithoutProgress >= MAX_TURNS_WITHOUT_PROGRESS {
                    AgentLogger.logAudit(level: .error, agent: "Orchestrator", message: "Aborting loop: No progress in \(turnsWithoutProgress) turns.")
                    await session.setFinalAnswer("Üzgünüm, araştırmada ilerleme kaydedemedim. Lütfen isteğinizi netleştirin veya farklı bir yaklaşım deneyin.")
                    break
                }
            } else {
                turnsWithoutProgress = 0 // Reset since model is taking action
                
                for toolCall in toolBlocks {
                    AgentLogger.logAudit(level: .info, agent: "Orchestrator", message: "Step: Executing \(toolCall.tool)")
                    
                    // Phase 1: Tool Enablement & Health Check (Goal 6)
                    let status = self.toolRegistry.getToolStatus(named: toolCall.tool)
                    let isEnabled = config.enabledTools[toolCall.tool] ?? true
                    
                    guard isEnabled && status.isAvailable else {
                        let reason = !isEnabled ? "Disabled by user" : "Auto-disabled due to repeated failures"
                        let obs = "Observation: Error - Tool '\(toolCall.tool)' is currently \(reason)."
                        await contextManager.addMessage(Message(role: "user", content: obs))
                        continue
                    }
                    
                    // Loop Detection
                    let currentToolJSON = (try? String(data: JSONEncoder().encode(toolCall), encoding: .utf8)) ?? ""
                    if currentToolJSON == lastToolCallJSON {
                        duplicateCount += 1
                        if duplicateCount >= 2 {
                            await contextManager.addMessage(Message(role: "user", content: "Observation: Error - Predicted loop. Please try a different strategy."))
                            continue
                        }
                    } else {
                        lastToolCallJSON = currentToolJSON
                        duplicateCount = 0
                    }
                    
                    // Tool Execution with Timeout
                    do {
                        let observation = try await withThrowingTaskGroup(of: String.self) { group in
                            group.addTask {
                                try await self.toolRegistry.execute(toolCall: toolCall, session: session)
                            }
                            group.addTask {
                                try await Task.sleep(nanoseconds: self.TOOL_TIMEOUT_NANOSECONDS)
                                throw ToolError.executionError("Timed out.")
                            }
                            guard let result = try await group.next() else { throw ToolError.executionError("No result") }
                            group.cancelAll()
                            return result
                        }
                        await contextManager.addMessage(Message(role: "user", content: "Observation: \(observation)"))
                    } catch {
                        AgentLogger.logAudit(level: .error, agent: "Orchestrator", message: "Tool Failed: \(error.localizedDescription)")
                        await contextManager.addMessage(Message(role: "user", content: "Observation: Error - \(error.localizedDescription)"))
                    }
                }
            }
            
            if foundFinalAnswer {
                await session.setFinalAnswer(finalAnswerText)
                break
            }
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
        
        throw InferenceError.localProviderUnavailable("No suitable provider found.")
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
