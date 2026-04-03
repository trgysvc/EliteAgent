import Foundation
import Combine

public actor OrchestratorRuntime {
    private let toolRegistry: ToolRegistry
    private let workspaceManager = WorkspaceManager.shared
    
    private let planner: PlannerAgent
    private let memory: MemoryAgent
    private let cloudProvider: CloudProvider
    private let localProvider: MLXProvider?
    private let bridgeProvider: BridgeProvider?
    private let bridge: HarpsichordBridge
    private let contextManager: DynamicContextManager
    private let bus: SignalBus
    private var emergencyBuffer: [Signal] = []
    
    private var onStepUpdate: (@Sendable (TaskStep) -> Void)?
    private var onStatusUpdate: (@Sendable (AgentStatus) -> Void)?
    private var onTokenUpdate: (@Sendable (TokenCount) -> Void)?
    
    public init(planner: PlannerAgent, memory: MemoryAgent, cloudProvider: CloudProvider, localProvider: MLXProvider? = nil, bridgeProvider: BridgeProvider? = nil, toolRegistry: ToolRegistry, bus: SignalBus, vaultManager: VaultManager) {
        self.planner = planner
        self.memory = memory
        self.cloudProvider = cloudProvider
        self.localProvider = localProvider
        self.bridgeProvider = bridgeProvider
        self.toolRegistry = toolRegistry
        self.bus = bus
        
        var providersList: [any LLMProvider] = [cloudProvider]
        if let l = localProvider { providersList.append(l) }
        if let b = bridgeProvider { providersList.append(b) }
        
        let tokenizer = BPETokenizer(vocab: [:], merges: [:]) 
        self.bridge = HarpsichordBridge(vaultManager: vaultManager, providers: providersList, tokenizer: tokenizer)
        self.contextManager = DynamicContextManager(maxTokens: cloudProvider.maxContextTokens, provider: cloudProvider)
    }
    
    public func setStepUpdateHandler(_ handler: @Sendable @escaping (TaskStep) -> Void) { self.onStepUpdate = handler }
    public func setStatusUpdateHandler(_ handler: @Sendable @escaping (AgentStatus) -> Void) { self.onStatusUpdate = handler }
    public func setTokenUpdateHandler(_ handler: @Sendable @escaping (TokenCount) -> Void) { self.onTokenUpdate = handler }
    
    public func executeTask(prompt: String, session: Session, complexity: Int = 3, forceProviders: [ProviderID]? = nil, config: InferenceConfig? = nil) async throws {
        await session.updateStatus(.thinking)
        onStatusUpdate?(.working)
        
        let effectiveConfig = config ?? InferenceConfig.default
        
        await contextManager.addMessage(Message(role: "user", content: prompt))
        var isRunning = true
        
        while isRunning {
            if Task.isCancelled {
                isRunning = false
                await session.updateStatus(.failed)
                return
            }
            
            if await session.isRecursionLimitReached() {
                await session.updateStatus(.failed)
                throw NSError(domain: "Orchestrator", code: 4, userInfo: [NSLocalizedDescriptionKey: "Max recursion depth reached"])
            }
            
            let currentRag = await memory.retrieveRelevantExperiences(query: prompt)
            let systemPrompt = await PlannerTemplate.generateAgenticPrompt(session: session, ragContext: currentRag)
            
            let request = CompletionRequest(
                taskID: session.id.uuidString,
                systemPrompt: systemPrompt,
                messages: await contextManager.getMessages(),
                maxTokens: 4096,
                temperature: 0.7,
                sensitivityLevel: .internal, 
                complexity: complexity
            )
            
            let startTime = Date()
            
            // Execute via Bridge with configuration
            let response = try await bridge.routeAndComplete(
                request: request, 
                preferredProvider: forceProviders?.first, 
                config: effectiveConfig
            )
            
            let duration = Date().timeIntervalSince(startTime)
            
            // v7.8.0: Sync actual provider with UI state (MainActor required for Observation)
            let providerID = response.providerUsed.rawValue
            let requestedProvider = forceProviders?.first ?? effectiveConfig.providerPriority.first
            let isFallback = response.providerUsed != requestedProvider
            
            await MainActor.run {
                AISessionState.shared.activeProvider = providerID
                AISessionState.shared.isFallbackActive = isFallback
                AISessionState.shared.lastInferenceLatency = duration
                if response.tokensUsed.completion > 0 {
                    AISessionState.shared.tokensPerSecond = Double(response.tokensUsed.completion) / duration
                }
                if isFallback {
                    AISessionState.shared.fallbackCount += 1
                }
            }
            
            await contextManager.addMessage(Message(role: "assistant", content: response.content))
            await session.addTokenUsage(response.tokensUsed)
            onTokenUpdate?(response.tokensUsed)
            
            // Parse Think/Final
            let blocks = ThinkParser.parse(response.content)
            if blocks.isEmpty {
                // Failsafe: If model doesn't use tags, treat entire response as final answer
                await session.setFinalAnswer(response.content)
                isRunning = false
                continue
            }

            for block in blocks {
                if let toolCall = block.toolCall {
                    onStepUpdate?(TaskStep(name: "Tool: \(toolCall.tool)", status: "working", latency: "ANE", thought: block.thought))
                    let result = try await toolRegistry.execute(toolCall: toolCall, session: session)
                    await contextManager.addMessage(Message(role: "user", content: "Observation: \(result)"))
                } else {
                    await session.setFinalAnswer(block.thought)
                    isRunning = false
                }
            }
        }
    }
}
