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
    private var onOverlayUpdate: (@Sendable (String?) -> Void)? // v13.4: Dedicated overlay channel
    
    private var turnsWithoutProgress = 0
    private let MAX_TURNS_WITHOUT_PROGRESS = 5
    private let MAX_PHASE_DURATION: TimeInterval = 120 // 2 minutes 
    private var isInterrupted = false
    private var activeContextManager: DynamicContextManager?
    private var sourcesAnalyzed = 0
    private var currentAction = "İşleniyor..."
    private var isResearchModeActive = false
    
    private var currentState: InferenceState = .idle
    private var currentTaskCategory: TaskCategory = .other
    private var isEscalatedToFullTools = false
    
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
    public func setOverlayUpdateHandler(_ handler: @escaping @Sendable (String?) -> Void) { self.onOverlayUpdate = handler }
    
    public func interrupt() { self.isInterrupted = true }
    
    public func executeTask(prompt: String, session: Session, complexity: Int, forceProviders: [ProviderID]? = nil, config: InferenceConfig) async throws {
        self.onStatusUpdate?(.working)
        self.isInterrupted = false
        self.currentState = .classifying
        self.currentTaskCategory = .other
        self.isEscalatedToFullTools = false
        self.sourcesAnalyzed = 0 
        
        let contextManager = DynamicContextManager(maxTokens: 8000, provider: cloudProvider)
        self.activeContextManager = contextManager
        let startTime = Date()
        
        let progressTask = Task {
            while !Task.isCancelled {
                let interval = await self.calculateHeartbeatInterval()
                try? await Task.sleep(nanoseconds: interval * 1_000_000_000)
                if Task.isCancelled { break } 
                let elapsed = Int(Date().timeIntervalSince(startTime))
                
                // v14.6: Global Safety Timeout
                if Double(elapsed) > self.MAX_PHASE_DURATION {
                    AgentLogger.logAudit(level: .error, agent: "Orchestrator", message: "🚨 [TIMEOUT] Phase stuck for \(elapsed)s. Force interrupting.")
                    self.isInterrupted = true
                }
                
                // v13.4: Move status from Chat Stream to Overlay
                self.onOverlayUpdate?("⚙️ \(self.currentAction) (\(elapsed)s)")
            }
        }
        
        defer { 
            progressTask.cancel() 
            // v10.5.2: Force-clear transient status indicators on completion
            self.onOverlayUpdate?(nil)
            Task {
                await TulparActor.shared.recordEvent(.taskCompleted(success: true))
                await DreamActor.shared.consolidateIfNeeded(memoryAgent: self.memory, cloudProvider: self.cloudProvider)
            }
        }
        
        await TulparActor.shared.recordEvent(.taskStarted)
        
        do {
            var turnCount = 0
            var healingAttempts = 0
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
                    self.currentTaskCategory = category
                    currentState = (category == .chat || category == .conversation) ? .chatting : .planning
                case .chatting:
                    try await handleChatting(prompt: prompt, provider: provider, context: contextManager, session: session)
                    currentState = .completed
                case .planning:
                    try await handlePlanning(prompt: prompt, provider: provider, context: contextManager, session: session, useSafeMode: healingAttempts > 0)
                    currentState = .executing
                    healingAttempts = 0 // Reset on successful transition
                case .executing:
                    do {
                        let (shouldContinue, finalAnswer) = try await handleExecution(provider: provider, context: contextManager, session: session, config: config, useSafeMode: healingAttempts > 0)
                        if !shouldContinue {
                            if let answer = finalAnswer { await session.setFinalAnswer(answer) }
                            currentState = .reviewing
                        } else {
                            currentState = .planning
                        }
                    } catch {
                        healingAttempts += 1
                        AgentLogger.logAudit(level: .warn, agent: "Orchestrator", message: "🛠 [STATE: HEALING] Tetiklendi (Attempt \(healingAttempts)): \(error.localizedDescription)")
                        
                        if healingAttempts >= 3 {
                            AgentLogger.logAudit(level: .error, agent: "Orchestrator", message: "🚨 [HEALING LIMIT] Max attempts reached.")
                            let history = await contextManager.getMessages()
                            let lastResponse = history.last?.content ?? ""
                            await session.setFinalAnswer(ThinkParser.cleanForUI(text: lastResponse))
                            currentState = .completed
                        } else {
                            if healingAttempts >= 2 {
                                self.isEscalatedToFullTools = true
                            }
                            
                            let errorMsg = """
                            SİSTEM UYARISI: Bir hata oluştu. 
                            HATA: \(error.localizedDescription)
                            
                            TALİMAT: Yukarıdaki hatayı gidererek asıl hedefine (**\(prompt)**) ulaşmak için yeni bir yol/plan oluştur. Workspace içindeki ilgisiz dosya değişikliklerine sapma, sadece orijinal görevi tamamla.
                            """
                            await contextManager.addMessage(Message(role: "user", content: errorMsg))
                            currentState = .planning // Retry planning with knowledge of the error
                        }
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
        
        // v11.6: Local-First Classification. Bypass cloud if local is ready.
        let activeProvider: any LLMProvider
        if let local = self.localProvider, local.isLoaded {
            activeProvider = local
        } else {
            activeProvider = provider
        }
        
        let systemPrompt = PromptRegistry.getPrompt(for: .classifier)
        let request = CompletionRequest(taskID: UUID().uuidString, systemPrompt: systemPrompt, messages: [Message(role: "user", content: prompt)], maxTokens: 500, sensitivityLevel: .public, complexity: 1)
        let response = try await activeProvider.complete(request, useSafeMode: false)
        AgentLogger.logAudit(level: .info, agent: "Orchestrator", message: "🏷 [CLASSIFY INPUT] \(prompt)")
        AgentLogger.logAudit(level: .info, agent: "Orchestrator", message: "🏷 [CLASSIFY RESPONSE] \(response.content)")
        
        // v11.0: Removed 'Heuristic Override'. Relying exclusively on model-driven classification.
        
        // v13.8: UNO Pure - Binary Category Detection (No JSON)
        let cleaned = response.content.trimmingCharacters(in: .whitespacesAndNewlines)
        if let category = TaskCategory.allCases.first(where: { cleaned.contains($0.rawValue) }) {
            return category
        }
        
        return .chat // Varsayılan: Güvenli sohbet modu
    }
    
    private func handleChatting(prompt: String, provider: any LLMProvider, context: DynamicContextManager, session: Session) async throws {
        self.currentAction = "Cevap Veriliyor..."
        let systemPrompt = PromptRegistry.getPrompt(for: .chatter(context: "Kullanıcı ile saf sohbet"))
        var history = await context.getMessages()
        if !history.contains(where: { $0.role == "user" && $0.content == prompt }) {
            history.append(Message(role: "user", content: prompt))
            await context.addMessage(Message(role: "user", content: prompt))
        }
        let isLocal = provider.providerType == .local
        let speedHint = isLocal ? "\nNOTE: Be concise. Direct answer only." : ""
        let request = CompletionRequest(taskID: UUID().uuidString, systemPrompt: systemPrompt + speedHint, messages: history, maxTokens: isLocal ? 1024 : 2000, sensitivityLevel: .public, complexity: 1)
        let response = try await provider.complete(request, useSafeMode: false)
        AgentLogger.logAudit(level: .info, agent: "Orchestrator", message: "💬 [CHAT INPUT] \(history.map { "[\($0.role)]: \($0.content)" }.joined(separator: " | "))")
        AgentLogger.logAudit(level: .info, agent: "Orchestrator", message: "💬 [CHAT RESPONSE] \(response.content)")
        self.onTokenUpdate?(response.tokensUsed, response.costUSD)
        self.onChatMessage?(ChatMessage(role: .assistant, content: response.content))
        await context.addMessage(Message(role: "assistant", content: response.content))
        await session.setFinalAnswer(response.content)
    }
    
    private func handlePlanning(prompt: String, provider: any LLMProvider, context: DynamicContextManager, session: Session, useSafeMode: Bool = false) async throws {
        self.currentAction = "Plan Hazırlanıyor..."
        
        // v11.8: Dynamic Tool Filtering & Escalation Logic
        var toolSubset: [any AgentTool]? = nil
        if !isEscalatedToFullTools {
            let toolNames = CategoryMapper.getTools(for: self.currentTaskCategory)
            toolSubset = toolNames.compactMap { self.toolRegistry.getTool(named: $0) }
            AgentLogger.logAudit(level: .info, agent: "Orchestrator", message: "🎯 [FILTERED MODE] Category: \(self.currentTaskCategory) | Tools: \(toolNames.joined(separator: ", "))")
        } else {
            AgentLogger.logAudit(level: .info, agent: "Orchestrator", message: "🚀 [FULL TOOLS MODE] Escalated due to complexity or errors.")
        }
        
        let systemPrompt = await PlannerTemplate.generateAgenticPrompt(
            session: session, 
            ragContext: "", 
            toolSubset: toolSubset
        )
        
        var history = await context.getMessages()
        if !history.contains(where: { $0.role == "user" && $0.content == prompt }) {
            history.append(Message(role: "user", content: prompt))
            await context.addMessage(Message(role: "user", content: prompt))
        }
        let isLocal = provider.providerType == .local
        let maxTokens = isLocal ? 1024 : 4000
        let speedHint = isLocal ? "\nCRITICAL: You are running on a local SLM. BE EXTREMELY CONCISE. Use tool calls immediately if needed. Minimize verbose dialogue." : ""
        
        let request = CompletionRequest(taskID: UUID().uuidString, systemPrompt: systemPrompt + speedHint, messages: history, maxTokens: maxTokens, sensitivityLevel: .public, complexity: isLocal ? 1 : 3)
        let response = try await provider.complete(request, useSafeMode: useSafeMode)
        AgentLogger.logAudit(level: .info, agent: "Orchestrator", message: "🧠 [PLAN RESPONSE] \(response.content)")
        if let think = response.thinkBlock { AgentLogger.logAudit(level: .info, agent: "Orchestrator", message: "🧠 [PLAN THINK] \(think)") }
        await context.addMessage(Message(role: "assistant", content: response.content))
    }
    
    private func handleExecution(provider: any LLMProvider, context: DynamicContextManager, session: Session, config: InferenceConfig, useSafeMode: Bool = false) async throws -> (Bool, String?) {
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
            
            // v13.8: UNO Pure - Priority for UBID Action
            if let ubid = output.ubid {
                toolBlocks.append(ToolCall(tool: "ubid_call", ubid: ubid, params: output.params ?? [:]))
            } else if output.type == .tool_call, let action = output.action {
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
            // v11.6: Placeholder Guard. Detect and block 'taslak veri' usage.
            let paramString = "\(toolCall.params)".lowercased()
            let placeholders = ["[ilgili bilgi]", "[bilgi]", "[tag]", "[buraya", "taslak", "[...]", "[ ]"]
            if placeholders.contains(where: { paramString.contains($0) }) {
                AgentLogger.logAudit(level: .warn, agent: "Orchestrator", message: "🛡 [PLACEHOLDER GUARD] Blocked tool: \(toolCall.tool)")
                let warning = "Observation: HATA! Bu parametrede taslak veri (placeholder) kullandın. LÜTFEN ÖNCE gerekli bilgiyi çekecek araçları (google_search, weather, read_file vb.) çalıştır ve gerçek veriyi aldıktan sonra bu işlemi yap."
                await context.addMessage(Message(role: "user", content: warning))
                return (true, nil) // Force back to planning
            }

            let actionName = self.getFriendlyActionName(for: toolCall.ubid != nil ? "ubid_\(toolCall.ubid!)" : toolCall.tool)
            self.currentAction = actionName
            self.onStepUpdate?(TaskStep(name: actionName, status: "Executing", latency: "0ms", thought: "UBID: \(toolCall.ubid ?? 0) | Params: \(toolCall.params)"))
            AgentLogger.logAudit(level: .info, agent: "Orchestrator", message: "🛠 [ACTION] \(toolCall.tool)")
            let result = try await self.toolRegistry.execute(toolCall: toolCall, session: session)
            AgentLogger.logAudit(level: .info, agent: "Orchestrator", message: "📡 [OBSERVATION] \(toolCall.tool) result size: \(result.count)")
            await context.addMessage(Message(role: "user", content: "Observation: \(result)"))
            if ["google_search", "web_search", "safari_automation", "web_fetch"].contains(toolCall.tool) { self.sourcesAnalyzed += 1 }
        }
        
        let systemPrompt = PromptRegistry.getPrompt(for: .executor(plan: "In Progress", forbiddenPatterns: []))
        let newHistory = await context.getMessages()
        let request = CompletionRequest(taskID: UUID().uuidString, systemPrompt: systemPrompt, messages: newHistory, maxTokens: 4000, sensitivityLevel: .public, complexity: 2)
        let response = try await provider.complete(request, useSafeMode: useSafeMode)
        AgentLogger.logAudit(level: .info, agent: "Orchestrator", message: "🛠 [EXEC INPUT] \(newHistory.map { "[\($0.role)]: \($0.content)" }.joined(separator: " | "))")
        AgentLogger.logAudit(level: .info, agent: "Orchestrator", message: "🛠 [EXEC RESPONSE] \(response.content)")
        self.onTokenUpdate?(response.tokensUsed, response.costUSD)
        await TokenBudgetActor.shared.recordUsage(tokens: response.tokensUsed.total, cost: response.costUSD)
        
        let cleanedResponse = response.content.trimmingCharacters(in: .whitespacesAndNewlines)
        let isNaturalLanguage = !cleanedResponse.hasPrefix("{") && !cleanedResponse.hasPrefix("```json")
        
        if isNaturalLanguage {
            self.onChatMessage?(ChatMessage(role: .assistant, content: response.content))
        }
        
        await context.addMessage(Message(role: "assistant", content: response.content))
        
        // v10.5.9: If we provided a natural language response, we assume the immediate execution sequence is done.
        // Returning (false, content) signals to transition to reviewing/completed.
        return (!isNaturalLanguage, isNaturalLanguage ? response.content : nil)
    }
    
    private func handleReview(prompt: String, provider: any LLMProvider, context: DynamicContextManager) async throws -> Bool {
        self.currentAction = "Sonuç Denetleniyor..."
        let lastHistory = await context.getMessages()
        let lastResponse = lastHistory.last?.content ?? ""
        let systemPrompt = PromptRegistry.getPrompt(for: .critic(task: prompt, output: lastResponse, criteria: "Accuracy"))
        let request = CompletionRequest(taskID: UUID().uuidString, systemPrompt: systemPrompt, messages: [], maxTokens: 500, sensitivityLevel: .public, complexity: 1)
        let response = try await provider.complete(request, useSafeMode: false)
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
    private static func truncateSemantically(_ content: String, targetTokens: Int) -> String {
        // v11.0: Using calibrated 4-char per token mapping for estimation
        let targetChars = targetTokens * 4
        return String(content.prefix(targetChars))
    }

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
