import Foundation
import OSLog

public actor OrchestratorRuntime {
    private let logger = Logger(subsystem: "com.elite.agent", category: "Orchestrator")
    
    private let planner: PlannerAgent
    private let memory: MemoryAgent
    private let cloudProvider: CloudProvider?
    private let localProvider: MLXProvider?
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
    private var lastReflectedObservation: String? = nil // v23.1: Guard against redundant responses 
    
    private var currentState: InferenceState = .idle
    private var currentTaskCategory: TaskCategory = .other
    private var isEscalatedToFullTools = false
    private var currentTurnObservations: [String] = [] // v21.0: Isolate current Turn data
    
    public init(
        planner: PlannerAgent,
        memory: MemoryAgent,
        cloudProvider: CloudProvider?,
        localProvider: MLXProvider?,
        toolRegistry: ToolRegistry,
        bus: SignalBus,
        vaultManager: VaultManager
    ) {
        self.planner = planner
        self.memory = memory
        self.cloudProvider = cloudProvider
        self.localProvider = localProvider
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
        case .custom(let pid, _, _, _, _): providerID = ProviderID(rawValue: pid) ?? .mlx
        }
        self.sessionContext.updateModel(providerID)
    }
    
    private func handleRetryParse() async {
        AgentLogger.logAudit(level: .warn, agent: "Orchestrator", message: "User requested a re-parse.")
        let retryMsg = "Observation: UNO Protokol İmzası okunamadı. Lütfen çıktıyı geçerli CALL([UBID]) formatında tekrarla."
        await activeContextManager?.addMessage(Message(role: "user", content: retryMsg))
    }
    
    public func setStepUpdateHandler(_ handler: @escaping @Sendable (TaskStep) -> Void) { self.onStepUpdate = handler }
    public func setChatMessageUpdateHandler(_ handler: @escaping @Sendable (ChatMessage) -> Void) { self.onChatMessage = handler }
    public func setStatusUpdateHandler(_ handler: @escaping @Sendable (AgentStatus) -> Void) { self.onStatusUpdate = handler }
    public func setTokenUpdateHandler(_ handler: @escaping @Sendable (TokenCount, Decimal) -> Void) { self.onTokenUpdate = handler }
    public func setOverlayUpdateHandler(_ handler: @escaping @Sendable (String?) -> Void) { self.onOverlayUpdate = handler }
    
    public func interrupt() { self.isInterrupted = true }
    
    public func executeTask(prompt: String, session: Session, complexity: Int, forceProviders: [ProviderID]? = nil, config: InferenceConfig, untrustedContext: [UntrustedData]? = nil) async throws {
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
            while currentState != .completed && turnCount < 15 {
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
                    let category = try await handleClassification(prompt: prompt, provider: provider, context: contextManager, untrustedContext: untrustedContext)
                    self.currentTaskCategory = category
                    currentState = (category == .chat || category == .conversation) ? .chatting : .planning
                case .chatting:
                    try await handleChatting(prompt: prompt, provider: provider, context: contextManager, session: session, untrustedContext: untrustedContext)
                    currentState = .completed
                case .planning:
                    self.currentTurnObservations.removeAll() // v21.0: Start fresh on new task
                    try await handlePlanning(prompt: prompt, provider: provider, context: contextManager, session: session, useSafeMode: healingAttempts > 0, untrustedContext: untrustedContext)
                    currentState = .executing
                    healingAttempts = 0 // Reset on successful transition
                case .executing:
                    do {
                        let (shouldContinue, finalAnswer) = try await handleExecution(provider: provider, context: contextManager, session: session, config: config, useSafeMode: healingAttempts > 0, untrustedContext: untrustedContext)
                        if !shouldContinue {
                            if let answer = finalAnswer {
                                let trimmed = answer.trimmingCharacters(in: .whitespacesAndNewlines)
                                if trimmed != "TASK_DONE" && !trimmed.isEmpty {
                                    // v24.0: Collision Guard. Enhanced semantic check.
                                    var shouldEcho = true
                                    if let last = lastReflectedObservation?.lowercased() {
                                        let normalizedAnswer = trimmed.lowercased()
                                        
                                        // Strategy A: Shared Digits (Temperatures/Dates)
                                        let answerDigits = normalizedAnswer.components(separatedBy: CharacterSet.decimalDigits.inverted).filter { !$0.isEmpty }
                                        let lastDigits = last.components(separatedBy: CharacterSet.decimalDigits.inverted).filter { !$0.isEmpty }
                                        let sharedDigits = Set(answerDigits).intersection(Set(lastDigits))
                                        
                                        // Strategy B: Token Overlap
                                        let stopWords: Set<String> = ["için", "olan", "ve", "ile", "hava", "durumu", "tahmini", "sıcaklık"]
                                        let answerTokens = Set(normalizedAnswer.components(separatedBy: .whitespacesAndNewlines).filter { $0.count > 2 && !stopWords.contains($0) })
                                        let lastTokens = Set(last.components(separatedBy: .whitespacesAndNewlines).filter { $0.count > 2 && !stopWords.contains($0) })
                                        let overlap = answerTokens.intersection(lastTokens)
                                        
                                        // If they share exact digits and a high % of tokens, it's a collision
                                        if !sharedDigits.isEmpty || (overlap.count >= 2 && overlap.count > lastTokens.count / 2) {
                                            AgentLogger.logAudit(level: .info, agent: "Orchestrator", message: "🛡 [v24.0 COLLISION GUARD] Suppressing redundant narrative. Shared Digits: \(sharedDigits), Overlap: \(overlap)")
                                            shouldEcho = false
                                        }
                                    }
                                    
                                    await session.setFinalAnswer(answer) 
                                    if shouldEcho {
                                        self.onChatMessage?(ChatMessage(role: .assistant, content: answer))
                                    }
                                }
                            }
                            currentState = .reviewing
                        } else {
                            // v23.1: Adaptive Convergence. After a tool call, return to PLANNING
                            // instead of forcing a redundant report. The model will see its own 
                            // reflected output and can choose to output DONE.
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
                            
                            TALİMAT: Yukarıdaki hatayı gidererek asıl hedefine (**\(prompt)**) ulaşmak için yeni bir yol/plan oluştur. 
                            KURAL: YALNIZCA <think> bloğu ve ardından gelen <final> içindeki CALL([UBID]) bloğunu kullan. Harici yapılandırılmış tablolar KESİNLİKLE YASAK.
                            💡 İPUCU: Araç açıklamalarını (descriptions) dikkatlice oku ve ZORUNLU parametreleri (location, text vb.) doldurduğundan emin ol.
                            KRİTİK: Eğer geçmiş mesajlarda kalan başka bir görevle uğraşıyorsan (örn: hava durumu) onu tamamen UNUT ve SADECE güncel göreve (**\(prompt)**) odaklan.
                            """
                            await contextManager.addMessage(Message(role: "user", content: errorMsg))
                            currentState = .planning // Retry planning with knowledge of the error
                        }
                    }
                case .reporting:
                    try await handleReporting(prompt: prompt, provider: provider, context: contextManager, session: session, untrustedContext: untrustedContext)
                    currentState = .reviewing
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
    
    private func handleClassification(prompt: String, provider: any LLMProvider, context: DynamicContextManager, untrustedContext: [UntrustedData]? = nil) async throws -> TaskCategory {
        self.currentAction = "İstek Sınıflandırılıyor..."
        AgentLogger.logAudit(level: .info, agent: "Orchestrator", message: "🏷 [CLASSIFY INPUT] \(prompt)")

        // v19.0: ANE Offloading - Attempt classification on the Neural Engine first
        let aneCategory = await ANEInferenceActor.shared.classifyIntent(prompt: prompt)
        if aneCategory != .other {
            AgentLogger.logAudit(level: .info, agent: "Orchestrator", message: "🏷 [ANE CLASSIFIED] Category: \(aneCategory)")
            return aneCategory
        }
        
        // v14.8: Deterministic Keyword Classification (Zero-Latency)
        // This ensures specialized tools like get_weather and telemetry are ALWAYS surfacing.
        let deterministicCategory = TaskClassifier().classify(prompt: prompt)
        if deterministicCategory != .other && deterministicCategory != .chat && deterministicCategory != .task {
            AgentLogger.logAudit(level: .info, agent: "Orchestrator", message: "🏷 [DETERMINISTIC CATEGORY] \(deterministicCategory)")
            return deterministicCategory
        }
        
        // v11.6: Local-First Classification. Bypass cloud if local is ready.
        let activeProvider: any LLMProvider
        if let local = self.localProvider, local.isLoaded {
            activeProvider = local
        } else {
            activeProvider = provider
        }
        
        let systemPrompt = PromptRegistry.getPrompt(for: .classifier)
        let request = CompletionRequest(taskID: UUID().uuidString, systemPrompt: systemPrompt, messages: [Message(role: "user", content: prompt)], maxTokens: 500, sensitivityLevel: .public, complexity: 1, untrustedContext: untrustedContext)
        let response = try await activeProvider.complete(request, useSafeMode: false)
        AgentLogger.logAudit(level: .info, agent: "Orchestrator", message: "🏷 [CLASSIFY RESPONSE] \(response.content)")
        
        // v11.0: Removed 'Heuristic Override'. Relying exclusively on model-driven classification.
        
        // v19.5: UNO Pure - Binary Category Detection (Tag-Based)
        let cleaned = response.content.uppercased()
        if cleaned.contains("[UNOB: TASK]") { return .task }
        if cleaned.contains("[UNOB: CHAT]") { return .chat }
        
        // Fallback to substring match for safety during migration
        if let category = TaskCategory.allCases.first(where: { cleaned.contains($0.rawValue.uppercased()) }) {
            return category
        }
        
        return .chat // Varsayılan: Güvenli sohbet modu
    }
    
    private func handleChatting(prompt: String, provider: any LLMProvider, context: DynamicContextManager, session: Session, untrustedContext: [UntrustedData]? = nil) async throws {
        self.currentAction = "Cevap Veriliyor..."
        let systemPrompt = PromptRegistry.getPrompt(for: .chatter(context: "Kullanıcı ile saf sohbet"))
        var history = await context.getMessages()
        if !history.contains(where: { $0.role == "user" && $0.content == prompt }) {
            history.append(Message(role: "user", content: prompt))
            await context.addMessage(Message(role: "user", content: prompt))
        }
        let isLocal = provider.providerType == .local
        let speedHint = isLocal ? "\n[CONSTRAINT: MIRROR USER LANGUAGE. BE CONCISE. DIRECT ANSWER ONLY.]" : ""
        let request = CompletionRequest(taskID: UUID().uuidString, systemPrompt: systemPrompt + speedHint, messages: history, maxTokens: isLocal ? 1024 : 2000, sensitivityLevel: .public, complexity: 1, untrustedContext: untrustedContext)
        let response = try await provider.complete(request, useSafeMode: false)
        AgentLogger.logAudit(level: .info, agent: "Orchestrator", message: "💬 [CHAT INPUT] \(history.map { "[\($0.role)]: \($0.content)" }.joined(separator: " | "))")
        AgentLogger.logAudit(level: .info, agent: "Orchestrator", message: "💬 [CHAT RESPONSE] \(response.content)")
        self.onTokenUpdate?(response.tokensUsed, response.costUSD)
        self.onChatMessage?(ChatMessage(role: .assistant, content: response.content))
        await context.addMessage(Message(role: "assistant", content: response.content))
        await session.setFinalAnswer(response.content)
    }
    
    private func handleReporting(prompt: String, provider: any LLMProvider, context: DynamicContextManager, session: Session, untrustedContext: [UntrustedData]? = nil) async throws {
        self.currentAction = "Bulgular Raporlanıyor..."
        AgentLogger.logAudit(level: .info, agent: "Orchestrator", message: "📝 [STATE: REPORTING]")
        
        let history = await context.getMessages()
        let lastObservation = history.last(where: { $0.role == "user" && $0.content.hasPrefix("Observation:") })?.content ?? ""
        
        // Use the dedicated executor prompt for narrative reporting
        let systemPrompt = PromptRegistry.getPrompt(for: .executor(plan: prompt, forbiddenPatterns: []))
        
        // v23.0: Tiered Context Architecture (Arşiv Memuru)
        let messages = await context.getMessages()
        var tieredHistory: [Message] = []
        
        if messages.count > 1 {
            // L1 Index: Keep the last 3 user-assistant pairs un-summarized
            let l1Threshold = max(0, messages.count - 6) 
            
            tieredHistory = messages.enumerated().map { index, msg in
                // System prompt (0) and L1 (Recent) are RAW
                if index == 0 || index >= l1Threshold {
                    return msg
                }
                
                // L2 (Warm Facts): Downgrade older technical observations to semantic facts
                if msg.role == "user" && msg.content.hasPrefix("Observation:") {
                    let observation = BasicObservation.from(rawResult: msg.content, toolName: "Historical Engine")
                    return Message(role: "user", content: observation.toFactString())
                }
                
                return msg
            }
        } else {
            tieredHistory = messages
        }
        
        // v23.0: L3 Cold Retrieval (RAG Injection)
        // If meta-intent is detected, actively pull matching facts from MemoryAgent (Experience Vault)
        let isLocal = provider.providerType == .local
        let request = CompletionRequest(taskID: UUID().uuidString, systemPrompt: systemPrompt, messages: tieredHistory, maxTokens: isLocal ? 1024 : 2000, sensitivityLevel: .public, complexity: 1, untrustedContext: untrustedContext)
        
        let response = try await provider.complete(request, useSafeMode: false)
        AgentLogger.logAudit(level: .info, agent: "Orchestrator", message: "📝 [REPORT RESPONSE] \(response.content)")
        
        // v20.6: Hallucination Suppression
        // We filter out any protocol junk (THINK, CALL, DONE) from appearing in the ChatView.
        let rawReport = response.content
        let cleanedReport = ThinkParser.cleanForUI(text: rawReport)
        
        // v20.6: Direct Reflection - The System reflects data immediately to UI
        // v23.1: Minimalist Deduplication. If a tool was run in this turn and reflected, 
        // we suppress the narrative if it provides no new information.
        let turnHasReflection = !self.currentTurnObservations.isEmpty
        
        if turnHasReflection && (cleanedReport.count < 150 || cleanedReport.uppercased().contains("DONE")) {
            AgentLogger.logAudit(level: .info, agent: "Orchestrator", message: "🛡 [v23.1 SILENCE GUARD] Information already reflected. Suppressing redundant report.")
            await context.addMessage(Message(role: "assistant", content: response.content))
            return
        }

        // Strictly block any 'thinking' or 'planning' hallucinations from the UI bubble
        if !cleanedReport.isEmpty && 
           !cleanedReport.uppercased().contains("CALL[") && 
           !cleanedReport.contains("THINK>") && 
           cleanedReport.uppercased() != "DONE" &&
           cleanedReport.uppercased() != "TASK_DONE" {
            await session.setFinalAnswer(cleanedReport)
            self.onChatMessage?(ChatMessage(role: .assistant, content: cleanedReport))
        } else if !lastObservation.isEmpty && (cleanedReport.uppercased() == "DONE" || cleanedReport.isEmpty) {
            // If model is just saying 'DONE', the direct reflection from handleExecution was already enough.
            AgentLogger.logAudit(level: .info, agent: "Orchestrator", message: "🛡 [REPORT MUTE] Model emitted protocol-only response. Relying on Direct Reflection.")
        }
        
        await context.addMessage(Message(role: "assistant", content: response.content))
    }
    
    private func handlePlanning(prompt: String, provider: any LLMProvider, context: DynamicContextManager, session: Session, useSafeMode: Bool = false, untrustedContext: [UntrustedData]? = nil) async throws {
        self.currentAction = "Plan Hazırlanıyor..."
        
        // v11.8: Dynamic Tool Filtering & Escalation Logic
        var toolSubset: [any AgentTool]? = nil
        if !isEscalatedToFullTools {
            let toolNames = CategoryMapper.getTools(for: self.currentTaskCategory)
            var subset: [any AgentTool] = []
            for name in toolNames {
                if let tool = await self.toolRegistry.getTool(named: name) {
                    subset.append(tool)
                }
            }
            toolSubset = subset
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
        let speedHint = isLocal ? "\n[CONSTRAINT: MIRROR USER LANGUAGE. BE EXTREMELY CONCISE but NEVER omit mandatory tool parameters (e.g. location, text, recipient).]" : ""
        
        let request = CompletionRequest(taskID: UUID().uuidString, systemPrompt: systemPrompt + speedHint, messages: history, maxTokens: maxTokens, sensitivityLevel: .public, complexity: isLocal ? 1 : 3, untrustedContext: untrustedContext)
        let response = try await provider.complete(request, useSafeMode: useSafeMode)
        AgentLogger.logAudit(level: .info, agent: "Orchestrator", message: "🧠 [PLAN RESPONSE] \(response.content)")
        if let think = response.thinkBlock { AgentLogger.logAudit(level: .info, agent: "Orchestrator", message: "🧠 [PLAN THINK] \(think)") }
        await context.addMessage(Message(role: "assistant", content: response.content))
    }
    
    private func handleExecution(provider: any LLMProvider, context: DynamicContextManager, session: Session, config: InferenceConfig, useSafeMode: Bool = false, untrustedContext: [UntrustedData]? = nil) async throws -> (Bool, String?) {
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
            throw ParserError.protocolMismatch("Model geçerli bir UNO planı veya yanıt üretmedi.")
        }
        
        // v19.7.10: Atomicity Guard - Force sequential execution for integrity
        if toolBlocks.count > 1 {
            AgentLogger.logAudit(level: .warn, agent: "Orchestrator", message: "🛡 [ATOMICITY GUARD] Blocked multi-call response (\(toolBlocks.count) steps).")
            let warning = "Observation: SİSTEM UYARISI: HATA! Aynı anda birden fazla CALL bloğu kullandın (Sıralı İcra Kuralı İhlali). Özellikle bağımlı görevlerde (arama yapıp dosyaya yazmak gibi) ÖNCE veriyi çeken aracı çalıştır, sonucunu (Observation) gör ve gerçek veriyi aldıktan sonra bir sonraki adımı planla. Şimdi sadece İLK öncelikli adımı icra et."
            await context.addMessage(Message(role: "user", content: warning))
            return (true, nil) // Force rethink
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
            // v21.0: Mission Guard - Veto unrequested structural modifications
            if ["shell_exec", "write_file"].contains(toolCall.tool) {
                let lowerParams = "\(toolCall.params)".lowercased()
                let remedialPatterns = ["purge", "free -m", "killall", "rm -rf", "sudo bash"]
                if remedialPatterns.contains(where: { lowerParams.contains($0) }) {
                    AgentLogger.logAudit(level: .warn, agent: "Orchestrator", message: "🛡 [MISSION GUARD] Blocked unrequested remedial action: \(toolCall.tool)")
                    let warning = "Observation: SİSTEM UYARISI: Bu eylem (sistem müdahalesi) mevcut görevin kapsamı dışındadır. Lütfen sadece kullanıcı tarafından talep edilen işlemi yap. Eğer bellek doluysa kullanıcıyı uyar ama müdahale etme."
                    await context.addMessage(Message(role: "user", content: warning))
                    return (true, nil)
                }
            }

            do {
                let result = try await self.toolRegistry.execute(toolCall: toolCall, session: session)
                self.currentTurnObservations.append(result)
                AgentLogger.logAudit(level: .info, agent: "Orchestrator", message: "📡 [OBSERVATION] \(toolCall.tool) result size: \(result.count)")
                
                // v22.0: Deep Continuity - Sync finding to the MemoryAgent (RAG)
                Task {
                    await self.memory.storeExperience(task: "Turn-based data find", solution: result)
                }
                
                // v21.1: Automatic Narrative Authority Trigger
                if result.contains("_WIDGET]") {
                    await session.markWidgetAsRendered()
                }
                
                // v20.6: Direct Reflection - The System reflects data immediately to UI
                // v21.2: Display Isolation - Only show the Widget if present, hide analytical text.
                if !result.isEmpty {
                    var displayContent = result.replacingOccurrences(of: "Observation:", with: "", options: .caseInsensitive)
                    
                    if displayContent.contains("_WIDGET]") {
                        let patterns = ["\\[SystemDNA_WIDGET\\].*", "\\[WeatherDNA_WIDGET\\].*", "\\[MusicDNA_WIDGET\\].*"]
                        for pattern in patterns {
                            if let range = displayContent.range(of: pattern, options: .regularExpression) {
                                displayContent = String(displayContent[range])
                                break
                            }
                        }
                    }
                    
                    self.lastReflectedObservation = displayContent.trimmingCharacters(in: .whitespacesAndNewlines)
                    self.onChatMessage?(ChatMessage(role: .assistant, content: self.lastReflectedObservation!))
                }
                
                await context.addMessage(Message(role: "user", content: "Observation: \(result)"))
            } catch let error as AgentToolError {
                // v10.5.6: Specific diagnostic for missing tools (UBID hallucination)
                if case .toolNotFound(let identifier) = error {
                    let diagnostic = "Observation: HATA! Araç bulunamadı (Identifier: \(identifier)). Lütfen UBID listesini tekrar kontrol et ve SADECE mevcut UBID'leri kullan. OS Version/Bilgi için UBID 58, Hava durumu için UBID 81 kullanmalısın."
                    await context.addMessage(Message(role: "user", content: diagnostic))
                    AgentLogger.logAudit(level: .error, agent: "Orchestrator", message: "🛠 [UBID DIAGNOSTIC] Hallucination detected for \(identifier). Sent correction.")
                } else {
                    await context.addMessage(Message(role: "user", content: "Observation: HATA! \(error.localizedDescription)"))
                }
                return (true, nil)
            }
            if ["google_search", "web_search", "safari_automation", "web_fetch"].contains(toolCall.tool) { self.sourcesAnalyzed += 1 }
        }
        
        // v19.7.12: Minimalist ReAct Loop
        // After any tool execution, we immediately return to Planning (true).
        // This leverages the Orchestrator's main loop (max 15 turns) as the safety net.
        // If the model produces natural language instead of tools, this method is never reached 
        // with tools, and the fallback logic handles completion.
        AgentLogger.logAudit(level: .info, agent: "Orchestrator", message: "🔄 [CYCLIC] Tool(s) executed. Returning to PLANNING for next turn.")
        return (true, nil)
    }
    
    private func handleReview(prompt: String, provider: any LLMProvider, context: DynamicContextManager) async throws -> Bool {
        self.currentAction = "Sonuç Denetleniyor..."
        let lastHistory = await context.getMessages()
        let lastResponse = lastHistory.last?.content ?? ""
        
        // v19.8: Contextual Review - Extract the last observation for the Critic
        let lastObservation = lastHistory.last(where: { $0.content.hasPrefix("Observation:") })?.content ?? "No observation found."
        
        let systemPrompt = PromptRegistry.getPrompt(for: .critic(task: prompt, observation: lastObservation, output: lastResponse))
        
        // v19.5: Binary Review (No JSON)
        let request = CompletionRequest(taskID: UUID().uuidString, systemPrompt: systemPrompt, messages: [], maxTokens: 500, sensitivityLevel: .public, complexity: 1)
        let response = try await provider.complete(request, useSafeMode: false)
        let resultString = response.content.uppercased()
        let passed = resultString.contains("UNOB:PASS") || resultString.contains("SCORE: 10") || resultString.contains("SCORE: 9")
        
        // v20.5: Programmatic Fidelity Guard (Veto Power)
        // If the pass is hallucinated (i.e. report is empty/DONE only but observation has data), we VETO.
        let reportText = lastResponse.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        if passed && (reportText == "DONE" || reportText == "<FINAL>DONE</FINAL>" || reportText.isEmpty) {
            if lastObservation != "No observation found." && lastObservation.count > 50 {
                AgentLogger.logAudit(level: .warn, agent: "Orchestrator", message: "🛡 [v20.5 VETO] Critic passed a silent report. Forcing failure.")
                return false // Vetoed! Force back to planning/reporting.
            }
        }
        
        AgentLogger.logAudit(level: .info, agent: "Orchestrator", message: "⚖️ [REVIEW] \(response.content)")
        
        return passed
    }
    
    private func resolveProvider(force: [ProviderID]?, config: InferenceConfig) throws -> any LLMProvider {
        let preferredModel = sessionContext.selectedModel
        if let force = force?.first {
            if force == .mlx, let p = localProvider { return p }
            if force == .openrouter, let p = cloudProvider { return p }
        }
        if preferredModel == .mlx, let p = localProvider { return p }
        if preferredModel == .openrouter, let p = cloudProvider { return p }
        for pid in config.providerPriority {
            if pid == .mlx, let p = localProvider { return p }
            if pid == .openrouter, let p = cloudProvider { return p }
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
