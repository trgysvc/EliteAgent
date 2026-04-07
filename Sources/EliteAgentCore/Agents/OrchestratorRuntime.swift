import Foundation
import OSLog

public actor OrchestratorRuntime {
    private let logger = Logger(subsystem: "com.elite.agent", category: "Orchestrator")
    
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
    private var activeContextManager: DynamicContextManager?
    private var sourcesAnalyzed = 0
    private var currentAction = "İşleniyor..."
    private var isResearchModeActive = false
    
    private var currentState: InferenceState = .idle
    
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
        self.sessionContext = SessionContext()
        
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
        AgentLogger.logAudit(level: .warn, agent: "Orchestrator", message: "User requested a re-parse.")
        let retryMsg = "Observation: JSON parse failed. Please provide output again in valid JSON format."
        await activeContextManager?.addMessage(Message(role: "user", content: retryMsg))
    }
    
    public func setStepUpdateHandler(_ handler: @escaping @Sendable (TaskStep) -> Void) { self.onStepUpdate = handler }
    public func setChatMessageUpdateHandler(_ handler: @escaping @Sendable (ChatMessage) -> Void) { self.onChatMessage = handler }
    public func setStatusUpdateHandler(_ handler: @escaping @Sendable (AgentStatus) -> Void) { self.onStatusUpdate = handler }
    public func setTokenUpdateHandler(_ handler: @escaping @Sendable (TokenCount, Decimal) -> Void) { self.onTokenUpdate = handler }
    
    public func interrupt() { self.isInterrupted = true }
    
    public func executeTask(prompt: String, session: Session, complexity: Int, forceProviders: [ProviderID]? = nil, config: InferenceConfig) async throws {
        self.onStatusUpdate?(.working)
        self.isInterrupted = false
        self.currentState = .classifying
        self.sourcesAnalyzed = 0 
        
        let contextManager = DynamicContextManager(maxTokens: 8000, provider: cloudProvider)
        self.activeContextManager = contextManager
        let startTime = Date()
        
        let progressTask = Task {
            while !Task.isCancelled {
                let interval = await self.calculateHeartbeatInterval()
                try? await Task.sleep(nanoseconds: interval * 1_000_000_000)
                if Task.isCancelled { break } // v10.5.2: Immediate drop out if cancelled
                let elapsed = Int(Date().timeIntervalSince(startTime))
                self.onChatMessage?(ChatMessage(role: .assistant, content: "⚙️ \(self.currentAction) (\(elapsed)s)", isStatus: true))
            }
        }
        
        defer { 
            progressTask.cancel() 
            // v10.5.2: Force-clear transient status indicators on completion
            self.onChatMessage?(ChatMessage(role: .assistant, content: "", isStatus: true))
            Task {
                await TulparActor.shared.recordEvent(.taskCompleted(success: true))
                await DreamActor.shared.consolidateIfNeeded(memoryAgent: self.memory, cloudProvider: self.cloudProvider)
            }
        }
        
        await TulparActor.shared.recordEvent(.taskStarted)
        
        do {
            var turnCount = 0
            while currentState != .completed && turnCount < 50 {
                turnCount += 1
                AgentLogger.logAudit(level: .info, agent: "Orchestrator", message: "🔄 [STATE: \(currentState.rawValue.uppercased())] Turn \(turnCount)")
                
                if isInterrupted {
                    currentState = .completed
                    await session.setFinalAnswer("İşlem kullanıcı tarafından durduruldu.")
                    break
                }
                
                let baseProvider = try resolveProvider(force: forceProviders, config: config)
                let targetID = await PerformanceArbiter.shared.resolveModelScale(originalID: baseProvider.providerID)
                let provider = targetID == baseProvider.providerID ? baseProvider : try resolveProvider(force: [targetID], config: config)

                switch currentState {
                case .classifying:
                    let category = try await handleClassification(prompt: prompt, provider: provider, context: contextManager)
                    currentState = (category == .chat || category == .conversation) ? .chatting : .planning
                case .chatting:
                    try await handleChatting(provider: provider, context: contextManager, session: session)
                    currentState = .completed
                case .planning:
                    try await handlePlanning(prompt: prompt, provider: provider, context: contextManager)
                    currentState = .executing
                case .executing:
                    let (shouldContinue, finalAnswer) = try await handleExecution(provider: provider, context: contextManager, session: session, config: config)
                    if !shouldContinue {
                        if let answer = finalAnswer { await session.setFinalAnswer(answer) }
                        currentState = .reviewing
                    }
                case .reviewing:
                    let passed = try await handleReview(prompt: prompt, provider: provider, context: contextManager)
                    currentState = passed ? .completed : .planning
                case .completed, .idle:
                    break
                }
            }
        } catch {
            AgentLogger.logAudit(level: .error, agent: "Orchestrator", message: "Critical failure: \(error.localizedDescription)")
            await session.setFinalAnswer("⚠️ Kritik hata: \(error.localizedDescription)")
        }
        
        self.currentState = .idle
        self.onStatusUpdate?(.idle)
    }
    
    private func handleClassification(prompt: String, provider: any LLMProvider, context: DynamicContextManager) async throws -> TaskCategory {
        self.currentAction = "İstek Sınıflandırılıyor..."
        let systemPrompt = PromptRegistry.getPrompt(for: .classifier)
        let request = CompletionRequest(taskID: UUID().uuidString, systemPrompt: systemPrompt, messages: [Message(role: "user", content: prompt)], maxTokens: 500, sensitivityLevel: .public, complexity: 1)
        let response = try await provider.complete(request)
        AgentLogger.logAudit(level: .info, agent: "Orchestrator", message: "🏷 [CLASSIFY INPUT] \(prompt)")
        AgentLogger.logAudit(level: .info, agent: "Orchestrator", message: "🏷 [CLASSIFY RESPONSE] \(response.content)")
        
        let cleaned = ThinkParser.extractJSONRobustly(response.content)
        if let data = cleaned.data(using: .utf8),
           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let catString = json["category"] as? String,
           let category = TaskCategory(rawValue: catString) {
            return category
        }
        return .chat // Varsayılan: Güvenli sohbet modu
    }
    
    private func handleChatting(provider: any LLMProvider, context: DynamicContextManager, session: Session) async throws {
        self.currentAction = "Cevap Veriliyor..."
        let systemPrompt = PromptRegistry.getPrompt(for: .chatter(context: "General Conversation"))
        let history = await context.getMessages()
        let request = CompletionRequest(taskID: UUID().uuidString, systemPrompt: systemPrompt, messages: history, maxTokens: 2000, sensitivityLevel: .public, complexity: 1)
        let response = try await provider.complete(request)
        AgentLogger.logAudit(level: .info, agent: "Orchestrator", message: "💬 [CHAT INPUT] \(history.map { "[\($0.role)]: \($0.content)" }.joined(separator: " | "))")
        AgentLogger.logAudit(level: .info, agent: "Orchestrator", message: "💬 [CHAT RESPONSE] \(response.content)")
        self.onTokenUpdate?(response.tokensUsed, response.costUSD)
        self.onChatMessage?(ChatMessage(role: .assistant, content: response.content))
        await context.addMessage(Message(role: "assistant", content: response.content))
        await session.setFinalAnswer(response.content)
    }
    
    private func handlePlanning(prompt: String, provider: any LLMProvider, context: DynamicContextManager) async throws {
        self.currentAction = "Plan Hazırlanıyor..."
        let allTools = toolRegistry.listTools().map { $0.name }
        let systemPrompt = PromptRegistry.getPrompt(for: .planner(tools: allTools, projectState: "Active", context: "N/A"))
        let history = await context.getMessages()
        let request = CompletionRequest(taskID: UUID().uuidString, systemPrompt: systemPrompt, messages: history, maxTokens: 4000, sensitivityLevel: .public, complexity: 3)
        let response = try await provider.complete(request)
        AgentLogger.logAudit(level: .info, agent: "Orchestrator", message: "🧠 [PLAN RESPONSE] \(response.content)")
        if let think = response.thinkBlock { AgentLogger.logAudit(level: .info, agent: "Orchestrator", message: "🧠 [PLAN THINK] \(think)") }
        await context.addMessage(Message(role: "assistant", content: response.content))
    }
    
    private func handleExecution(provider: any LLMProvider, context: DynamicContextManager, session: Session, config: InferenceConfig) async throws -> (Bool, String?) {
        let history = await context.getMessages()
        let lastMessage = history.last?.content ?? ""
        let parsedOutputs = try ThinkParser.parseOutputs(from: lastMessage)
        
        var toolBlocks: [ToolCall] = []
        var finalAnswer: String? = nil
        
        for output in parsedOutputs {
            // v10.5.6: Priority for structured steps array
            if let steps = output.steps {
                toolBlocks.append(contentsOf: steps)
            } 
            
            // Legacy compatibility for single tool calls
            if output.type == .tool_call, let action = output.action {
                toolBlocks.append(ToolCall(tool: action, params: output.params ?? [:]))
            } else if output.type == .response, let text = output.content {
                finalAnswer = text
            }
        }
        
        if toolBlocks.isEmpty { 
            // If no tools but we have a final answer, return it.
            if let answer = finalAnswer { return (false, answer) }
            // If no tools and no answer, the model might have failed to plan.
            throw ParserError.emptyJSON("Model geçerli bir plan veya yanıt üretmedi.")
        }
        
        for toolCall in toolBlocks {
            let actionName = self.getFriendlyActionName(for: toolCall.tool)
            self.currentAction = actionName
            self.onStepUpdate?(TaskStep(name: actionName, status: "Executing", latency: "0ms", thought: "Parametreler: \(toolCall.params)"))
            AgentLogger.logAudit(level: .info, agent: "Orchestrator", message: "🛠 [ACTION] \(toolCall.tool)")
            let result = try await self.toolRegistry.execute(toolCall: toolCall, session: session)
            AgentLogger.logAudit(level: .info, agent: "Orchestrator", message: "📡 [OBSERVATION] \(toolCall.tool) result size: \(result.count)")
            await context.addMessage(Message(role: "user", content: "Observation: \(result)"))
            if ["google_search", "web_search", "safari_automation", "web_fetch"].contains(toolCall.tool) { self.sourcesAnalyzed += 1 }
        }
        
        let systemPrompt = PromptRegistry.getPrompt(for: .executor(plan: "In Progress", forbiddenPatterns: []))
        let newHistory = await context.getMessages()
        let request = CompletionRequest(taskID: UUID().uuidString, systemPrompt: systemPrompt, messages: newHistory, maxTokens: 4000, sensitivityLevel: .public, complexity: 2)
        let response = try await provider.complete(request)
        AgentLogger.logAudit(level: .info, agent: "Orchestrator", message: "🛠 [EXEC INPUT] \(newHistory.map { "[\($0.role)]: \($0.content)" }.joined(separator: " | "))")
        AgentLogger.logAudit(level: .info, agent: "Orchestrator", message: "🛠 [EXEC RESPONSE] \(response.content)")
        self.onTokenUpdate?(response.tokensUsed, response.costUSD)
        await TokenBudgetActor.shared.recordUsage(tokens: response.tokensUsed.total, cost: response.costUSD)
        self.onChatMessage?(ChatMessage(role: .assistant, content: response.content))
        await context.addMessage(Message(role: "assistant", content: response.content))
        return (true, nil)
    }
    
    private func handleReview(prompt: String, provider: any LLMProvider, context: DynamicContextManager) async throws -> Bool {
        self.currentAction = "Sonuç Denetleniyor..."
        let lastHistory = await context.getMessages()
        let lastResponse = lastHistory.last?.content ?? ""
        let systemPrompt = PromptRegistry.getPrompt(for: .critic(task: prompt, output: lastResponse, criteria: "Accuracy"))
        let request = CompletionRequest(taskID: UUID().uuidString, systemPrompt: systemPrompt, messages: [], maxTokens: 500, sensitivityLevel: .public, complexity: 1)
        let response = try await provider.complete(request)
        AgentLogger.logAudit(level: .info, agent: "Orchestrator", message: "⚖️ [REVIEW] \(response.content)")
        return response.content.contains("\"passed\": true") || response.content.contains("passed: true")
    }
    
    private func resolveProvider(force: [ProviderID]?, config: InferenceConfig) throws -> any LLMProvider {
        let preferredModel = sessionContext.selectedModel
        if let force = force?.first {
            if force == .mlx, let p = localProvider { return p }
            if force == .openrouter { return cloudProvider }
            if force == .bridge, let p = bridgeProvider { return p }
        }
        if preferredModel == .mlx, let p = localProvider { return p }
        if preferredModel == .openrouter { return cloudProvider }
        for pid in config.providerPriority {
            if pid == .mlx, let p = localProvider { return p }
            if pid == .openrouter { return cloudProvider }
            if pid == .bridge, let p = bridgeProvider { return p }
        }
        if config.strictLocal { throw InferenceError.localProviderUnavailable("Titan hazır değil.") }
        throw InferenceError.localProviderUnavailable("No provider.")
    }
    
    private func calculateHeartbeatInterval() async -> UInt64 {
        let thermal = ProcessInfo.processInfo.thermalState
        switch thermal {
        case .serious, .critical: return 5
        case .fair, .nominal: return 2
        @unknown default: return 3
        }
    }
    
    private func getFriendlyActionName(for tool: String) -> String {
        switch tool {
        case "google_search", "web_search", "native_browser": return "İnternette Arama Yapılıyor..."
        case "safari_automation", "web_fetch", "read_file": return "İçerik Okunuyor..."
        case "media_control", "music_dna": return "Medya Ayarlanıyor..."
        case "system_volume", "brightness_control", "sleep_control": return "Sistem Ayarlanıyor..."
        case "app_discovery", "shortcut_discovery", "shortcut_execution": return "Sistem Komutları Taranıyor..."
        case "file_manager", "write_file": return "Dosya İşlemi Yapılıyor..."
        case "shell_tool", "patch_tool", "git_tool": return "Sistem Komutu Çalıştırılıyor..."
        case "whatsapp", "messenger", "email", "mail": return "Mesaj İletişimi Kuruluyor..."
        case "weather", "calculator", "timer": return "Uygulama Verisi Sorgulanıyor..."
        case "vision", "chicago_vision": return "Görüntü Analizi Yapılıyor..."
        default: return "Sistem Çağrısı Yapılıyor..."
        }
    }
}

public struct BriefFormatter {
    public static func format(_ content: String) -> String {
        let lines = content.components(separatedBy: .newlines)
        let bulletLines = lines.filter { 
            let t = $0.trimmingCharacters(in: .whitespacesAndNewlines)
            return t.hasPrefix("-") || t.hasPrefix("*") || t.hasPrefix("•") 
        }
        if bulletLines.isEmpty {
            let sentences = content.components(separatedBy: ". ")
            return sentences.prefix(2).joined(separator: ". ") + "..."
        }
        return bulletLines.joined(separator: "\n")
    }
}
