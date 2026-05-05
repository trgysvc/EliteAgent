import Foundation
import OSLog

public actor OrchestratorRuntime {
    private let logger = Logger(subsystem: "com.elite.agent", category: "Orchestrator")
    
    private let planner: PlannerAgent
    private let memory: MemoryAgent
    private let cloudProvider: (any LLMProvider)?
    private let localProvider: (any LLMProvider)?
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
    private let MAX_PHASE_DURATION: TimeInterval = 600.0 // 10 minutes (Increased for extensive tasks)
    private var isInterrupted = false
    private var activeContextManager: DynamicContextManager?
    private var sourcesAnalyzed = 0
    private var currentAction = "Processing..."
    private var isResearchModeActive = false
    private var lastReflectedObservation: String? = nil // v23.1: Guard against redundant responses 
    
    private var currentState: InferenceState = .idle
    private var currentTaskCategory: TaskCategory = .other
    private var isEscalatedToFullTools = false
    private var currentTurnObservations: [String] = [] // v21.0: Isolate current Turn data
    private var lastPlanningResponse: CompletionResponse? = nil // Native tool calling: holds mlx-swift-lm parsed tool calls
    private let loopDetector = ToolLoopDetector() // v12.0: Deterministic Loop Guard
    private let chunker = AdaptiveTaskChunker() // v27.0: Adaptive Workload Partitioning
    private var activeChunks: [AdaptiveTaskChunker.TaskChunk] = []
    private var currentChunkIndex = 0
    private var isChunkedMode = false
    private var trajectoryRecorder: TrajectoryRecorder? // v27.0: Observability
    private var bootstrapContext: String = "" // v27.0: Workspace context
    
    // v7.0 Stability: Global Session Control
    @MainActor
    private static var isSystemPaused: Bool = false

    public static func pauseAllSessions() {
        Task { @MainActor in
            isSystemPaused = true
            AgentLogger.logAudit(level: .warn, agent: "Orchestrator", message: "🛑 SYSTEM PAUSED: Global session freeze engaged due to critical pressure.")
        }
    }

    public static func resumeAllSessions() {
        Task { @MainActor in
            isSystemPaused = false
            AgentLogger.logAudit(level: .info, agent: "Orchestrator", message: "🟢 SYSTEM RESUMED: Global session freeze lifted.")
        }
    }

    public static func triggerCompaction() {
        AgentLogger.logAudit(level: .info, agent: "Orchestrator", message: "📦 [COMPACTION] Memory pressure warning: proactive consolidation triggered.")
    }
    
    public init(
        planner: PlannerAgent,
        memory: MemoryAgent,
        cloudProvider: (any LLMProvider)?,
        localProvider: (any LLMProvider)?,
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

        Task {
            await ProactiveMemoryPressureMonitor.shared.startMonitoring()
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
        let retryMsg = "Observation: [PROTOCOL_ERROR] UNO Protocol Signature could not be read. Please repeat the output in valid CALL([UBID]) format."
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
        self.trajectoryRecorder = TrajectoryRecorder(sessionId: session.id)
        await trajectoryRecorder?.record(.userMessage(content: prompt, timestamp: Date()))
        
        // v27.0: Workspace Bootstrap Loading
        self.bootstrapContext = await WorkspaceBootstrapLoader.load(workspaceURL: session.workspaceURL)
        if !bootstrapContext.isEmpty {
            AgentLogger.logAudit(level: .info, agent: "Orchestrator", message: "🚀 [BOOTSTRAP] Injected workspace context (\(bootstrapContext.count) chars)")
        }
        
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
            var planningTurns = 0
            let maxPlanningTurns = 10
            var healingAttempts = 0
            while currentState != .completed && turnCount < 20 {
                turnCount += 1
                
                if currentState == .planning {
                    planningTurns += 1
                    if planningTurns > maxPlanningTurns {
                        AgentLogger.logAudit(level: .error, agent: "Orchestrator", message: "🚨 [TURN LIMIT] Maximum planning turns (\(maxPlanningTurns)) reached. Breaking loop.")
                        await session.setFinalAnswer("Görev çok fazla adım gerektiriyor veya döngüye girdi. Lütfen görevi basitleştirin veya daha fazla bilgi verin.")
                        currentState = .completed
                        break
                    }
                }
                AgentLogger.logAudit(level: .info, agent: "Orchestrator", message: "🔄 [STATE: \(currentState.rawValue.uppercased())] Turn \(turnCount)")
                
                if isInterrupted {
                    currentState = .completed
                    await session.setFinalAnswer("Process interrupted by user.")
                    break
                }
                
                // v7.0 Stability: Global Pause Check (MainActor Isolated)
                while await MainActor.run(body: { Self.isSystemPaused }) {
                    try? await Task.sleep(nanoseconds: 1_000_000_000) // Sleep for 1s and re-check
                    if isInterrupted { break }
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
                    if let loopWarning = await loopDetector.detectLoop() {
                        await contextManager.addMessage(Message(role: "user", content: "Observation: [LOOP_GUARD] \(loopWarning)"))
                        AgentLogger.logAudit(level: .warn, agent: "Orchestrator", message: "🛡 [LOOP DETECTED] \(loopWarning)")
                        await trajectoryRecorder?.record(.loopDetected(detector: "v2", count: 1, timestamp: Date()))
                    }
                    
                    // v27.0: Context Window Guard — check before every planning turn
                    let guardMessages = await contextManager.getMessages()
                    let guardResult = ContextWindowGuard.evaluate(
                        messages: guardMessages,
                        systemPromptTokens: 1_500,
                        maxTokens: (provider.providerType == .local) ? 8_192 : 128_000
                    )
                    switch guardResult {
                    case .compact(let msg, _, _):
                        AgentLogger.logAudit(level: .warn, agent: "Orchestrator", message: "📦 \(msg)")
                        let tokensBefore = ContextWindowGuard.estimateTokens(messages: await contextManager.getMessages())
                        try await contextManager.compress(sessionID: UUID().uuidString, localProvider: self.localProvider)
                        let tokensAfter = ContextWindowGuard.estimateTokens(messages: await contextManager.getMessages())
                        await trajectoryRecorder?.record(.compaction(tokensBefore: tokensBefore, tokensAfter: tokensAfter, timestamp: Date()))
                    case .block(let msg, _, _):
                        AgentLogger.logAudit(level: .error, agent: "Orchestrator", message: "🚫 \(msg)")
                        // Force compaction before blocking
                        let tokensBefore = ContextWindowGuard.estimateTokens(messages: await contextManager.getMessages())
                        try await contextManager.compress(sessionID: UUID().uuidString, localProvider: self.localProvider)
                        let tokensAfter = ContextWindowGuard.estimateTokens(messages: await contextManager.getMessages())
                        await trajectoryRecorder?.record(.compaction(tokensBefore: tokensBefore, tokensAfter: tokensAfter, timestamp: Date()))
                        await contextManager.addMessage(Message(role: "user", content: "Observation: \(msg) Context was compacted. Be concise."))
                    case .warn(let msg, let used, let max):
                        AgentLogger.logAudit(level: .warn, agent: "Orchestrator", message: "⚠️ \(msg)")
                        await contextManager.addMessage(Message(role: "user", content: "Observation: \(msg)"))
                        await trajectoryRecorder?.record(.contextGuard(usedTokens: used, maxTokens: max, action: "warn", timestamp: Date()))
                    case .ok:
                        break
                    }
                    
                    self.currentTurnObservations.removeAll() // v21.0: Start fresh on new task
                    try await handlePlanning(prompt: prompt, provider: provider, context: contextManager, session: session, useSafeMode: healingAttempts > 0, untrustedContext: untrustedContext)
                    currentState = .executing
                    healingAttempts = 0 // Reset on successful transition
                case .executing:
                    do {
                        let (shouldContinue, finalAnswer) = try await handleExecution(provider: provider, context: contextManager, session: session, config: config, useSafeMode: healingAttempts > 0, untrustedContext: untrustedContext)
                        if !shouldContinue {
                            if let answer = finalAnswer {
                                let trimmed = answer.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
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
                                        let answerTokens = Set(normalizedAnswer.components(separatedBy: CharacterSet.whitespacesAndNewlines).filter { $0.count > 2 && !stopWords.contains($0) })
                                        let lastTokens = Set(last.components(separatedBy: CharacterSet.whitespacesAndNewlines).filter { $0.count > 2 && !stopWords.contains($0) })
                                        let overlap = answerTokens.intersection(lastTokens)
                                        
                                        // Strategy C: Mandatory Widget Silence (User Request)
                                        if last.contains("_widget]") {
                                            AgentLogger.logAudit(level: .info, agent: "Orchestrator", message: "🛡 [WIDGET SILENCE] Suppressing narrative because a widget is rendered.")
                                            shouldEcho = false
                                        }
                                        
                                        // If they share exact digits and a high % of tokens, it's a collision
                                        if shouldEcho && (!sharedDigits.isEmpty || (overlap.count >= 2 && overlap.count > lastTokens.count / 2)) {
                                            AgentLogger.logAudit(level: .info, agent: "Orchestrator", message: "🛡 [v24.0 COLLISION GUARD] Suppressing redundant narrative. Shared Digits: \(sharedDigits), Overlap: \(overlap)")
                                            shouldEcho = false
                                        }
                                    }
                                    
                                    await session.setFinalAnswer(answer) 
                                    if shouldEcho {
                                        self.onChatMessage?(ChatMessage(role: .assistant, content: answer))
                                    }
                                } else if trimmed == "TASK_DONE" {
                                    await session.setFinalAnswer("Görev başarıyla tamamlandı.")
                                }
                            } else {
                                // v21.0: Fallback for missing finalAnswer
                                await session.setFinalAnswer("İşlem tamamlandı.")
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
                        AgentLogger.logAudit(level: .warn, agent: "Orchestrator", message: "🛠 [STATE: HEALING] Triggered (Attempt \(healingAttempts)): \(error.localizedDescription)")
                        
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
                            SYSTEM WARNING: An error occurred.
                            ERROR: \(error.localizedDescription)
                            
                            INSTRUCTION: Resolve the error above and create a new path/plan to reach your goal (**\(prompt)**).
                            RULE: Use ONLY the <think> block followed by the <final> block with CALL([UBID]). External structured tables are strictly FORBIDDEN.
                            💡 TIP: Read tool descriptions carefully and fill in MANDATORY parameters.
                            🚨 CRITICAL SAFETY: If you received this error due to a long bash command chain, DO NOT REPEAT THE SAME COMMAND. Use simpler commands or create a Swift script. Swift scripts are more stable on macOS.
                            CRITICAL: Forget any previous tasks from older messages and focus ONLY on the current goal.
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
                    if passed {
                        currentState = .completed
                    } else {
                        // v24.1: Critic Feedback Injection
                        // Add English Critic error to context.
                        let criticWarning = "Observation: [CRITIC_FAIL] The system auditor determined that the task is not complete or objective evidence is missing. Please review the TASK PROGRESS STATUS and continue executing the remaining steps sequentially."
                        await contextManager.addMessage(Message(role: "user", content: criticWarning))
                        currentState = .planning
                    }
                case .completed, .idle:
                    break
                }
            }
        } catch {
            AgentLogger.logAudit(level: .error, agent: "Orchestrator", message: "Critical failure: \(error.localizedDescription)")
            await session.setFinalAnswer("⚠️ Critical error: \(error.localizedDescription)")
        }
        
        self.currentState = .idle
        self.onStatusUpdate?(.idle)
    }
    
    private func handleClassification(prompt: String, provider: any LLMProvider, context: DynamicContextManager, untrustedContext: [UntrustedData]? = nil) async throws -> TaskCategory {
        self.currentAction = "Classifying Request..."
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
        
        return .chat // Default: Safe chat mode
    }
    
    private func handleChatting(prompt: String, provider: any LLMProvider, context: DynamicContextManager, session: Session, untrustedContext: [UntrustedData]? = nil) async throws {
        self.currentAction = "Responding..."
        let isLocal = provider.providerType == .local

        // Local models (Qwen 3.5): use a minimal, non-rule-based prompt to prevent
        // the model from entering structured "Thinking Process:" output mode.
        // The [RULE: ...] format triggers analytical chain-of-thought in Qwen 3.5.
        let systemPrompt: String
        let maxTokens: Int
        if isLocal {
            systemPrompt = "Sen yardımsever bir asistansın. Kullanıcının dilinde kısa ve doğal yanıt ver. Düşünce sürecini açıklama, doğrudan cevap ver."
            maxTokens = 1024 // 256 was too small: model's <think> block consumed the budget, leaving only truncated text.
        } else {
            systemPrompt = PromptRegistry.getPrompt(for: .chatter(context: "Pure conversation with user"))
            maxTokens = 2000
        }

        var history = await context.getMessages()
        if !history.contains(where: { $0.role == "user" && $0.content == prompt }) {
            history.append(Message(role: "user", content: prompt))
            await context.addMessage(Message(role: "user", content: prompt))
        }
        let request = CompletionRequest(taskID: UUID().uuidString, systemPrompt: systemPrompt, messages: history, maxTokens: maxTokens, sensitivityLevel: .public, complexity: 1, untrustedContext: untrustedContext)
        let response = try await provider.complete(request, useSafeMode: false)
        AgentLogger.logAudit(level: .info, agent: "Orchestrator", message: "💬 [CHAT INPUT] \(history.map { "[\($0.role)]: \($0.content)" }.joined(separator: " | "))")
        AgentLogger.logAudit(level: .info, agent: "Orchestrator", message: "💬 [CHAT RESPONSE] \(response.content)")
        self.onTokenUpdate?(response.tokensUsed, response.costUSD)

        // Strip any remaining thinking preamble and raw markdown syntax for display.
        // MLXProvider already extracts <think> blocks, but "Thinking Process:" format may remain.
        let afterThinkStrip = stripThinkingOutput(from: ThinkParser.cleanForUI(text: response.content))
        let stripped = afterThinkStrip.isEmpty ? response.content : afterThinkStrip
        let displayContent = isLocal ? stripRawMarkdown(stripped) : stripped

        self.onChatMessage?(ChatMessage(role: .assistant, content: displayContent))
        await context.addMessage(Message(role: "assistant", content: response.content))
        await session.setFinalAnswer(displayContent)
    }
    
    private func handleReporting(prompt: String, provider: any LLMProvider, context: DynamicContextManager, session: Session, untrustedContext: [UntrustedData]? = nil) async throws {
        self.currentAction = "Reporting Findings..."
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
        await trajectoryRecorder?.record(.assistantMessage(content: response.content, timestamp: Date()))
        
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
        let upperCleaned = cleanedReport.uppercased()
        let hasProtocol = upperCleaned.contains("CALL(") || upperCleaned.contains("WITH {") || upperCleaned.contains("<FINAL>")
        let hasThinking = upperCleaned.contains("<THINK>") || upperCleaned.contains("THINK>")
        
        if !cleanedReport.isEmpty && !hasProtocol && !hasThinking &&
           upperCleaned != "DONE" && upperCleaned != "TASK_DONE" {
            await session.setFinalAnswer(cleanedReport)
            self.onChatMessage?(ChatMessage(role: .assistant, content: cleanedReport))
        } else if (upperCleaned == "DONE" || cleanedReport.isEmpty || upperCleaned == "TASK_DONE") {
            // v23.5: Structured Completion Bubble
            let summary = lastObservation.isEmpty ? "İşlem başarıyla tamamlandı." : lastObservation
            let completionMsg = "[TASK_COMPLETED]\nTask completed.\n\(summary)"
            await session.setFinalAnswer(completionMsg)
            self.onChatMessage?(ChatMessage(role: .assistant, content: completionMsg))
            AgentLogger.logAudit(level: .info, agent: "Orchestrator", message: "🛡 [COMPLETION BUBBLE] Task finished with summary: \(summary)")
        }
        
        await context.addMessage(Message(role: "assistant", content: response.content))
    }
    
    private func handlePlanning(prompt: String, provider: any LLMProvider, context: DynamicContextManager, session: Session, useSafeMode: Bool = false, untrustedContext: [UntrustedData]? = nil) async throws {
        self.currentAction = "Preparing Plan..."
        
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
        
        let baseSystemPrompt = await PlannerTemplate.generateAgenticPrompt(
            session: session,
            ragContext: self.bootstrapContext, // Inject bootstrap context here
            toolSubset: toolSubset
        )
        
        // v1.1: Task Progress Injection — her planning turuna güncel adım durumunu ekle
        let progressBlock = await session.progressTracker.statusBlock()
        let systemPrompt = progressBlock.isEmpty ? baseSystemPrompt : baseSystemPrompt + progressBlock
        if !progressBlock.isEmpty {
            AgentLogger.logAudit(level: .info, agent: "Orchestrator", message: "📋 [PROGRESS INJECT] \(progressBlock.prefix(200))")
        }
        
        var history = await context.getMessages()
        if !history.contains(where: { $0.role == "user" && $0.content == prompt }) {
            history.append(Message(role: "user", content: prompt))
            await context.addMessage(Message(role: "user", content: prompt))
        }
        let isLocal = provider.providerType == .local
        let maxTokens = isLocal ? 1024 : 4000

        // Native tool calling path: local providers use mlx-swift-lm xmlFunction format (Qwen 3.5).
        // The chat template injects tool definitions; the model responds with <tool_call> blocks
        // which mlx-swift-lm parses into CompletionResponse.toolCalls.
        let finalSystemPrompt: String
        let requestTools: [[String: any Sendable]]?
        if isLocal {
            let nativeBase = PlannerTemplate.generateNativeToolCallingSystemPrompt(workspace: session.workspaceURL.path)
            finalSystemPrompt = progressBlock.isEmpty ? nativeBase : nativeBase + progressBlock
            let specs = buildToolSpecs(for: toolSubset ?? [])
            requestTools = specs.isEmpty ? nil : specs
        } else {
            let speedHint = "\n[CONSTRAINT: MIRROR USER LANGUAGE. BE EXTREMELY CONCISE but NEVER omit mandatory tool parameters (e.g. location, text, recipient).]"
            finalSystemPrompt = systemPrompt + speedHint
            requestTools = nil
        }

        let request = CompletionRequest(
            taskID: UUID().uuidString,
            systemPrompt: finalSystemPrompt,
            messages: history,
            maxTokens: maxTokens,
            sensitivityLevel: .public,
            complexity: isLocal ? 1 : 3,
            untrustedContext: untrustedContext,
            tools: requestTools
        )
        let response = try await provider.complete(request, useSafeMode: useSafeMode)
        AgentLogger.logAudit(level: .info, agent: "Orchestrator", message: "🧠 [PLAN RESPONSE] \(response.content)")
        if let calls = response.toolCalls, !calls.isEmpty {
            AgentLogger.logAudit(level: .info, agent: "Orchestrator", message: "🎯 [PLAN NATIVE CALLS] \(calls.map { $0.tool }.joined(separator: ", "))")
        }
        await trajectoryRecorder?.record(.assistantMessage(content: response.content, timestamp: Date()))
        if let think = response.thinkBlock { AgentLogger.logAudit(level: .info, agent: "Orchestrator", message: "🧠 [PLAN THINK] \(think)") }

        // Store full response so handleExecution can pick up native tool calls.
        self.lastPlanningResponse = isLocal ? response : nil

        // v1.1: İlk planning turunda model adım listesi üretirse tracker'a kaydet
        let tracker = session.progressTracker
        let isFirstPlan = await !tracker.isInitialized
        if isFirstPlan {
            let steps = PlannerTemplate.extractSteps(from: response.content)
            if !steps.isEmpty {
                await tracker.setSteps(steps)
                AgentLogger.logAudit(level: .info, agent: "Orchestrator", message: "📋 [STEPS REGISTERED] \(steps.count) adım kaydedildi: \(steps.joined(separator: " | "))")
            }
        }

        await context.addMessage(Message(role: "assistant", content: response.content))
    }
    
    private func handleExecution(provider: any LLMProvider, context: DynamicContextManager, session: Session, config: InferenceConfig, useSafeMode: Bool = false, untrustedContext: [UntrustedData]? = nil) async throws -> (Bool, String?) {
        let history = await context.getMessages()
        let lastMessage = history.last?.content ?? ""

        var toolBlocks: [ToolCall] = []
        var finalAnswer: String? = nil

        // Native tool calling path: mlx-swift-lm parsed tool calls from last planning turn.
        // These bypass ThinkParser since the model used xmlFunction format, not CALL([UBID]).
        if let nativeResp = lastPlanningResponse {
            self.lastPlanningResponse = nil
            if let nativeCalls = nativeResp.toolCalls, !nativeCalls.isEmpty {
                toolBlocks = nativeCalls
                AgentLogger.logAudit(level: .info, agent: "Orchestrator", message: "🎯 [NATIVE EXEC] Using \(nativeCalls.count) mlx-swift-lm tool call(s).")
            } else if !nativeResp.content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                // Model responded with text (conversational answer), not tool calls.
                return (false, ThinkParser.cleanForUI(text: nativeResp.content))
            }
            // If both empty: fall through to ThinkParser on lastMessage as safety net.
        }

        if toolBlocks.isEmpty {
            // Legacy path: parse CALL([UBID]) / <final> blocks from last assistant message.
            let parsedOutputs = try ThinkParser.parseOutputs(from: lastMessage)

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
        }

        if toolBlocks.isEmpty {
            // If no tools but we have a final answer, return it.
            if let answer = finalAnswer {
                // v12.1: Evidence Guard for DONE hallucination
                if answer.uppercased().contains("DONE") {
                    let lastObs = currentTurnObservations.last?.lowercased() ?? ""
                    let verificationKeywords = ["ls", "total", "content", "file", "id3", "lufs", "metadata", "status", "output", "read", "docker", "find", "git", "python", "swift", "success", "result", "started", "created"]
                    let errorIndicators = ["error", "failed", "could not", "not found", "exception", "failed assertion", "denied", "permission"]
                    
                    let hasEvidence = verificationKeywords.contains(where: { lastObs.contains($0) })
                    let hasError = errorIndicators.contains(where: { lastObs.contains($0) })
                    
                    if (!hasEvidence || hasError) && !currentTurnObservations.isEmpty {
                        AgentLogger.logAudit(level: .warn, agent: "Orchestrator", message: "🛡 [EVIDENCE GUARD] Rejected DONE. \(hasError ? "Error detected" : "No verification").")
                        await trajectoryRecorder?.record(.evidenceGuardVeto(reason: "No verification in history", timestamp: Date()))
                        let warning = """
                        Observation: [CRITIC_FAIL] You declared DONE, but the last tool output (\(lastObs.prefix(50))...) does not provide objective verification of success. 
                        You MUST verify the state (e.g., list files with 'ls' or check content with 'cat' or 'tag_check') before concluding. 
                        If your previous command failed or produced no output, TROUBLESHOOT and FIX the command (check paths, quotes, and parameters) instead of assuming success.
                        """
                        await context.addMessage(Message(role: "user", content: warning))
                        return (true, nil) // Force rethink
                    }
                }
                return (false, answer) 
            }
            // If no tools and no answer, the model might have failed to plan.
            throw ParserError.protocolMismatch("Model failed to produce a valid UNO plan or response.")
        }
        
        // v19.7.10: Atomicity Guard - Force sequential execution for integrity
        if toolBlocks.count > 1 {
            AgentLogger.logAudit(level: .warn, agent: "Orchestrator", message: "🛡 [ATOMICITY GUARD] Blocked multi-call response (\(toolBlocks.count) steps).")
            let warning = "Observation: SYSTEM WARNING: ERROR! You used multiple CALL blocks at once (Sequential Execution Rule Violation). For dependent tasks, execute the data-gathering tool FIRST, see the Observation, and then plan the next step based on real data. Execute ONLY the first priority step now."
            await context.addMessage(Message(role: "user", content: warning))
            return (true, nil) // Force rethink
        }
        
        for toolCall in toolBlocks {
            // v11.6: Placeholder Guard. Detect and block 'taslak veri' usage.
            let paramString = "\(toolCall.params)".lowercased()
            let placeholders = ["[ilgili bilgi]", "[bilgi]", "[tag]", "[buraya", "taslak", "[...]", "[ ]"]
            if placeholders.contains(where: { paramString.contains($0) }) {
                AgentLogger.logAudit(level: .warn, agent: "Orchestrator", message: "🛡 [PLACEHOLDER GUARD] Blocked tool: \(toolCall.tool)")
                let warning = "Observation: ERROR! You used placeholder data in this parameter. Please FIRST run tools to fetch the required information (google_search, weather, read_file, etc.) and perform this action ONLY after receiving real data."
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
                    let warning = "Observation: SYSTEM WARNING: This action (system intervention) is outside the scope of the current task. Please perform only the action requested by the user. If memory is full, warn the user but do not intervene."
                    await context.addMessage(Message(role: "user", content: warning))
                    return (true, nil)
                }
            }
            
            // v24.2: Anti-Repetition Guard
            // Model aynı komutu/parametreleri tekrar tekrar üretiyorsa döngüyü (loop) kır.
            let toolSignature = "\(toolCall.tool):\(toolCall.params)"
            if await session.hasToolBeenExecuted(signature: toolSignature) {
                AgentLogger.logAudit(level: .warn, agent: "Orchestrator", message: "🛡 [ANTI-REPETITION GUARD] Blocked identical tool call: \(toolSignature)")
                let warning = "Observation: SYSTEM WARNING: ERROR! You have already executed this command/tool. Please check the TASK PROGRESS STATUS table and execute the NEXT uncompleted step. DO NOT REPEAT THE SAME OPERATION."
                await context.addMessage(Message(role: "user", content: warning))
                return (true, nil) // Force rethink
            }
            
            await session.markToolAsExecuted(signature: toolSignature)

            let startTime = Date()
            let ubidValue = Int64(toolCall.ubid ?? 0)
            await trajectoryRecorder?.record(.toolCall(name: toolCall.tool, ubid: ubidValue, params: toolCall.params, timestamp: startTime))

            do {
                let result = try await self.toolRegistry.execute(toolCall: toolCall, session: session)
                let durationMs = Int(Date().timeIntervalSince(startTime) * 1000)
                await trajectoryRecorder?.record(.toolResult(name: toolCall.tool, ubid: ubidValue, result: result, durationMs: durationMs, timestamp: Date()))
                self.currentTurnObservations.append(result)
                AgentLogger.logAudit(level: .info, agent: "Orchestrator", message: "📡 [OBSERVATION] \(toolCall.tool) result size: \(result.count)")
                
                // v1.0: Shell Error Detection — if ShellTool tagged the output with [SHELL_ERROR],
                // consult SelfHealingEngine and inject corrective guidance before re-planning.
                if result.hasPrefix("[SHELL_ERROR]") {
                    let strategy = await SelfHealingEngine.shared.analyze(error: result.lowercased(), tool: toolCall.tool)
                    let healingHint = strategy?.description ?? "Fix the command and wrap file paths in single quotes (')."
                    let shellErrorObservation = """
                    Observation: [SHELL_ERROR] Command failed.
                    Raw Error: \(result)
                    
                    \(healingHint)
                    
                    IMPORTANT: Analyze this error. DO NOT repeat the same command. Fix the file path and try again.
                    """
                    await context.addMessage(Message(role: "user", content: shellErrorObservation))
                    AgentLogger.logAudit(level: .warn, agent: "Orchestrator", message: "🛠 [SHELL_HEAL] Injected correction for: \(strategy?.name ?? "UNKNOWN")")
                    return (true, nil) // Return to planning with correction context
                }
                
                // v12.0 → v27.0: Record for Loop Detection (OpenClaw-Inspired)
                // Records both the call and its outcome for no-progress detection.
                await loopDetector.recordOutcome(toolName: toolCall.tool, params: toolCall.params, result: result)
                
                // v27.0: Adaptive Task Chunking (Analytical Hardening)
                // If the observation contains a massive list of items, we intercept and chunk it.
                if result.count > 2000 {
                    let items = self.extractWorkItems(from: result)
                    if items.count > 20 {
                        let hwState = await AdaptiveTaskChunker.captureHardwareState()
                        let budget = AdaptiveTaskChunker.ContextBudget(
                            maxTokens: (provider.providerType == .local) ? 8192 : 128000,
                            currentUsedTokens: ContextWindowGuard.estimateTokens(messages: await context.getMessages())
                        )
                        
                        let decision = await chunker.chunkIfNeeded(items: items, hardwareState: hwState, contextBudget: budget)
                        if case .chunked(let chunks) = decision {
                            self.activeChunks = chunks
                            self.currentChunkIndex = 0
                            self.isChunkedMode = true
                            
                            let firstChunk = chunks[0]
                            let chunkReason = "High workload detected (\(items.count) items). Partitioning into \(chunks.count) chunks to preserve context window."
                            let overlayMsg = AdaptiveTaskChunker.progressNotification(chunk: firstChunk, completedItems: 0, totalItems: items.count, reason: chunkReason)
                            self.onOverlayUpdate?(overlayMsg)
                            
                            let chunkedObservation = """
                            Observation: [ADAPTIVE_CHUNKING] \(chunkReason)
                            
                            CURRENT BATCH (Chunk 1/\(chunks.count)):
                            \(firstChunk.items.joined(separator: "\n"))
                            
                            INSTRUCTIONS: Process ONLY these \(firstChunk.items.count) items. Once finished, conclude this turn. The system will automatically provide the next batch.
                            """
                            AgentLogger.logAudit(level: .info, agent: "Orchestrator", message: "⚙️ [CHUNKING] Split \(items.count) items into \(chunks.count) chunks.")
                            await context.addMessage(Message(role: "user", content: chunkedObservation))
                            return (true, nil)
                        }
                    }
                }

                // v1.1: TaskProgressTracker — başarılı tool çalışmasını adım ilerlemesi olarak kaydet
                let tracker = session.progressTracker
                if await tracker.isInitialized {
                    // Sonraki bekleyen adımı bu gözlemle tamamla
                    if let pendingIdx = await tracker.nextPendingStepIndex() {
                        await tracker.markCompleted(stepIndex: pendingIdx, evidence: result)
                        AgentLogger.logAudit(level: .info, agent: "Orchestrator", message: "📋 [STEP DONE] Step \(pendingIdx) completed. Remaining: \(await tracker.steps.filter { !$0.isCompleted }.count)")
                    }
                }
                
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
                        let patterns = ["\\[SystemDNA_WIDGET\\][\\s\\S]*", "\\[WeatherDNA_WIDGET\\][\\s\\S]*", "\\[MusicDNA_WIDGET\\][\\s\\S]*"]
                        for pattern in patterns {
                            if let range = displayContent.range(of: pattern, options: .regularExpression) {
                                displayContent = String(displayContent[range])
                                // Widget's are still reflected so they render.
                                self.lastReflectedObservation = displayContent.trimmingCharacters(in: .whitespacesAndNewlines)
                                self.onChatMessage?(ChatMessage(role: .assistant, content: self.lastReflectedObservation!))
                                break
                            }
                        }
                    }
                }
                
                await context.addMessage(Message(role: "user", content: "Observation: \(result)"))
            } catch let error as AgentToolError {
                // v10.5.6: Specific diagnostic for missing tools (UBID hallucination)
                if case .toolNotFound(let identifier) = error {
                    let diagnostic = "Observation: [TOOL_ERROR] Tool not found (Identifier: \(identifier)). Please double check the UBID list and use ONLY available UBIDs. For OS Version/Info use UBID 58, for Weather use UBID 81."
                    await context.addMessage(Message(role: "user", content: diagnostic))
                    AgentLogger.logAudit(level: .error, agent: "Orchestrator", message: "🛠 [UBID DIAGNOSTIC] Hallucination detected for \(identifier). Sent correction.")
                } else {
                    await context.addMessage(Message(role: "user", content: "Observation: [TOOL_ERROR] \(error.localizedDescription)"))
                }
                return (true, nil)
            }
            if ["google_search", "web_search", "safari_automation", "web_fetch"].contains(toolCall.tool) { self.sourcesAnalyzed += 1 }
        }
        
        // v27.0: Chunked Mode Continuation (Analytical Hardening)
        // If we are in chunked mode and the model signals completion of the current batch, feed the next one.
        if isChunkedMode {
            let lastAssistantMsg = lastMessage.uppercased()
            if lastAssistantMsg.contains("DONE") || lastAssistantMsg.contains("TASK_DONE") {
                currentChunkIndex += 1
                if currentChunkIndex < activeChunks.count {
                    let nextChunk = activeChunks[currentChunkIndex]
                    let totalItems = activeChunks.reduce(0) { $0 + $1.items.count }
                    let completedSoFar = activeChunks.prefix(currentChunkIndex).reduce(0) { $0 + $1.items.count }
                    
                    let overlayMsg = AdaptiveTaskChunker.progressNotification(chunk: nextChunk, completedItems: completedSoFar, totalItems: totalItems, reason: "Moving to next data batch.")
                    self.onOverlayUpdate?(overlayMsg)
                    
                    let nextObservation = """
                    Observation: [CHUNK_CONTINUATION] Batch \(currentChunkIndex + 1)/\(activeChunks.count) started.
                    
                    NEXT ITEMS TO PROCESS:
                    \(nextChunk.items.joined(separator: "\n"))
                    
                    INSTRUCTIONS: Continue your work with these items. Do NOT repeat previous items.
                    """
                    AgentLogger.logAudit(level: .info, agent: "Orchestrator", message: "⚙️ [CHUNKING] Moving to chunk \(currentChunkIndex + 1)/\(activeChunks.count)")
                    await context.addMessage(Message(role: "user", content: nextObservation))
                    return (true, nil) // Force back to planning with new data
                } else {
                    // All chunks completed
                    AgentLogger.logAudit(level: .info, agent: "Orchestrator", message: "⚙️ [CHUNKING] All chunks processed successfully.")
                    isChunkedMode = false
                    activeChunks = []
                    currentChunkIndex = 0
                    self.onOverlayUpdate?(nil)
                }
            }
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
        self.currentAction = "Auditing Results..."
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
        // v23.2 FIX: Do NOT veto if the observation contains a WIDGET tag or structured report header.
        let reportText = lastResponse.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        if passed && (reportText == "DONE" || reportText == "<FINAL>DONE</FINAL>" || reportText.isEmpty) {
            let isStructured = lastObservation.contains("_WIDGET]") || 
                              lastObservation.contains("--- Project Map") || 
                              lastObservation.contains("Ekran Analiz Raporu")
            
            if !isStructured && lastObservation != "No observation found." && lastObservation.count > 50 {
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
        if config.strictLocal { throw InferenceError.localProviderUnavailable("Titan is not ready.") }
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
        case "google_search", "web_search", "native_browser": return "Searching the Web..."
        case "safari_automation", "web_fetch", "read_file": return "Reading Content..."
        case "media_control", "music_dna": return "Configuring Media..."
        case "system_volume", "brightness_control", "sleep_control": return "Adjusting System Settings..."
        case "app_discovery", "shortcut_discovery", "shortcut_execution": return "Scanning System Commands..."
        case "file_manager", "write_file": return "Performing File Operation..."
        case "shell_tool", "patch_tool", "git_tool": return "Executing System Command..."
        case "whatsapp", "messenger", "email", "mail": return "Establishing Messaging Communication..."
        case "weather", "calculator", "timer": return "Querying Application Data..."
        case "vision", "chicago_vision": return "Performing Image Analysis..."
        default: return "Executing System Call..."
        }
    }
    
    /// Removes raw markdown syntax characters from text for plain-text display in chat bubbles.
    private func stripRawMarkdown(_ text: String) -> String {
        var result = text
        // Bold/italic markers
        result = result.replacingOccurrences(of: "\\*{1,3}([^*]+)\\*{1,3}", with: "$1", options: .regularExpression)
        // Headings
        result = result.replacingOccurrences(of: "^#{1,6}\\s+", with: "", options: [.regularExpression, .anchored])
        result = result.replacingOccurrences(of: "\n#{1,6}\\s+", with: "\n", options: .regularExpression)
        // Bullet points (normalize * / - bullets to plain dash-free text)
        result = result.replacingOccurrences(of: "^[\\*\\-]\\s+", with: "", options: [.regularExpression, .anchored])
        result = result.replacingOccurrences(of: "\n[\\*\\-]\\s+", with: "\n", options: .regularExpression)
        // Inline code
        result = result.replacingOccurrences(of: "`([^`]+)`", with: "$1", options: .regularExpression)
        // Quoted strings: remove surrounding quotes if entire response is wrapped
        let trimmed = result.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.hasPrefix("\"") && trimmed.hasSuffix("\"") && trimmed.count > 2 {
            result = String(trimmed.dropFirst().dropLast())
        }
        return result.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Strips "Thinking Process:" structured reasoning blocks that Qwen 3.5 leaks into chat output.
    /// These appear when the model's analytical mode is triggered by rule-heavy system prompts.
    private func stripThinkingOutput(from text: String) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)

        // Detect structured "Thinking Process:" preamble — model leaked its chain-of-thought.
        // Find the last numbered/bulleted conclusion section and extract text after it.
        let thinkingMarkers = ["Thinking Process:", "Chain of Thought:", "Let me think", "Step 1:", "1. **Analyze"]
        let hasThinkingPreamble = thinkingMarkers.contains(where: { trimmed.lowercased().hasPrefix($0.lowercased()) })

        guard hasThinkingPreamble else { return trimmed }

        // Find the last "Final decision:" or "Final Polish:" or similar conclusion markers.
        let conclusionMarkers = ["Final decision:", "Final Polish:", "Final answer:", "Output:", "Response:"]
        var bestRange: Range<String.Index>? = nil
        for marker in conclusionMarkers {
            if let range = trimmed.range(of: marker, options: [.caseInsensitive, .backwards]) {
                if bestRange == nil || range.lowerBound > bestRange!.lowerBound {
                    bestRange = range
                }
            }
        }

        if let conclusionRange = bestRange {
            // Extract the text after the last conclusion marker line
            let afterConclusion = String(trimmed[conclusionRange.upperBound...])
                .trimmingCharacters(in: .whitespacesAndNewlines)
            // Skip to the next line (the actual answer)
            let lines = afterConclusion.components(separatedBy: .newlines)
            let answerLines = lines.drop(while: { $0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty })
            let answer = answerLines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
            if !answer.isEmpty { return answer }
        }

        // Fallback: if last paragraph (after last blank line) is short, use it as the answer.
        let paragraphs = trimmed.components(separatedBy: "\n\n")
        if let last = paragraphs.last?.trimmingCharacters(in: .whitespacesAndNewlines),
           !last.isEmpty, last.count < 300 {
            return last
        }

        return trimmed
    }

    private func extractWorkItems(from text: String) -> [String] {
        let lines = text.components(separatedBy: .newlines)
        return lines.filter { line in
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            // Path-like, ID-like, or list-like patterns
            return (trimmed.contains("/") && !trimmed.contains(" ")) ||
                   (trimmed.contains(".") && !trimmed.contains(" ") && trimmed.count > 5) ||
                   (trimmed.count >= 2 && Int(trimmed) != nil)
        }.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
    }

    /// Builds mlx-swift-lm ToolSpec dictionaries for the given tools.
    /// Format: OpenAI function-calling schema ([String: any Sendable]).
    /// Only tools with known parameter schemas are included (others are skipped).
    private func buildToolSpecs(for tools: [any AgentTool]) -> [[String: any Sendable]] {
        let schemaMap: [String: [String: any Sendable]] = [
            "shell_exec": toolSpec(name: "shell_exec", description: "Execute a zsh terminal command on macOS. Use single quotes for paths.", properties: [
                "command": prop("string", "The zsh command to execute. Wrap every path in single quotes.")
            ], required: ["command"]),
            "read_file": toolSpec(name: "read_file", description: "Read a file from disk and return its contents.", properties: [
                "path": prop("string", "Absolute path to the file.")
            ], required: ["path"]),
            "write_file": toolSpec(name: "write_file", description: "Write content to a file on disk.", properties: [
                "path": prop("string", "Absolute path to the file."),
                "content": prop("string", "The content to write.")
            ], required: ["path", "content"]),
            "get_weather": toolSpec(name: "get_weather", description: "Get current weather for a location.", properties: [
                "location": prop("string", "City name or region."),
                "day": prop("string", "Optional day offset (e.g. 'today', 'tomorrow').")
            ], required: ["location"]),
            "web_search": toolSpec(name: "web_search", description: "Search the web and return results.", properties: [
                "query": prop("string", "The search query.")
            ], required: ["query"]),
            "app_launcher": toolSpec(name: "app_launcher", description: "Launch a macOS application by name.", properties: [
                "app_name": prop("string", "Application name (e.g. 'Safari', 'Finder').")
            ], required: ["app_name"]),
            "send_message_via_whatsapp_or_imessage": toolSpec(name: "send_message_via_whatsapp_or_imessage", description: "Send an iMessage or WhatsApp message.", properties: [
                "recipient": prop("string", "Recipient name or phone number."),
                "message": prop("string", "Message text to send."),
                "platform": prop("string", "Platform: 'imessage' or 'whatsapp'.")
            ], required: ["recipient", "message"]),
            "id3_processor": toolSpec(name: "id3_processor", description: "Process and embed ID3 metadata tags into MP3 files in a directory.", properties: [
                "directory": prop("string", "Path to the directory containing MP3 files.")
            ], required: ["directory"]),
            "blender_3d": toolSpec(name: "blender_3d", description: "Execute Blender 3D operations via Python bpy script.", properties: [
                "action": prop("string", "Action type: execute_script, create_scene, add_mesh, add_light, render."),
                "script": prop("string", "Python bpy code for execute_script action.")
            ], required: ["action"]),
            "media_control": toolSpec(name: "media_control", description: "Control media playback (play, pause, next, previous, volume).", properties: [
                "action": prop("string", "Action: play, pause, next, previous, volume_up, volume_down.")
            ], required: ["action"]),
            "visual_audit": toolSpec(name: "visual_audit", description: "Take a screenshot and analyze screen windows, UI elements, and visual data.", properties: [
                "target": prop("string", "Target window or screen area to analyze. Leave empty for full screen.")
            ], required: []),
            "analyze_image": toolSpec(name: "analyze_image", description: "Analyze a local image file for text and interactive elements.", properties: [
                "path": prop("string", "Absolute path to the image file.")
            ], required: ["path"]),
            "web_fetch": toolSpec(name: "web_fetch", description: "Fetch the content of a specific URL and return it as text.", properties: [
                "url": prop("string", "The URL to fetch.")
            ], required: ["url"]),
            "git_action": toolSpec(name: "git_action", description: "Execute git operations (status, commit, push, pull, diff, log).", properties: [
                "action": prop("string", "Git action: status, commit, push, pull, diff, log, clone."),
                "path": prop("string", "Repository path."),
                "message": prop("string", "Commit message (for commit action).")
            ], required: ["action"]),
            "patch_file": toolSpec(name: "patch_file", description: "Apply a unified diff patch to a file.", properties: [
                "path": prop("string", "Absolute path to the file to patch."),
                "patch": prop("string", "Unified diff content to apply.")
            ], required: ["path", "patch"]),
            "get_system_info": toolSpec(name: "get_system_info", description: "Get macOS system information (CPU, RAM, storage, OS version).", properties: [:], required: []),
            "get_system_telemetry": toolSpec(name: "get_system_telemetry", description: "Get real-time system telemetry: CPU load, memory pressure, thermal state.", properties: [:], required: [])
        ]

        return tools.compactMap { schemaMap[$0.name] }
    }

    private func toolSpec(name: String, description: String, properties: [String: [String: any Sendable]], required: [String]) -> [String: any Sendable] {
        var params: [String: any Sendable] = ["type": "object", "required": required]
        params["properties"] = properties as [String: any Sendable]
        return [
            "type": "function",
            "function": ["name": name, "description": description, "parameters": params] as [String: any Sendable]
        ]
    }

    private func prop(_ type: String, _ description: String) -> [String: any Sendable] {
        return ["type": type, "description": description]
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
