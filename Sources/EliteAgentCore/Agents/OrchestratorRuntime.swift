import Foundation
import Combine

public actor OrchestratorRuntime {
    private let toolRegistry: ToolRegistry
    private let workspaceManager = WorkspaceManager.shared
    
    private let planner: PlannerAgent
    private let memory: MemoryAgent
    private let cloudProvider: CloudProvider
    private let contextManager: DynamicContextManager
    
    private var onStepUpdate: (@Sendable (TaskStep) -> Void)?
    private var onStatusUpdate: (@Sendable (AgentStatus) -> Void)?
    
    public func setStepUpdateHandler(_ handler: @Sendable @escaping (TaskStep) -> Void) {
        self.onStepUpdate = handler
    }

    public func setStatusUpdateHandler(_ handler: @Sendable @escaping (AgentStatus) -> Void) {
        self.onStatusUpdate = handler
    }
    
    public init(planner: PlannerAgent, memory: MemoryAgent, cloudProvider: CloudProvider, toolRegistry: ToolRegistry) {
        self.planner = planner
        self.memory = memory
        self.cloudProvider = cloudProvider
        self.toolRegistry = toolRegistry
        self.contextManager = DynamicContextManager(maxTokens: cloudProvider.maxContextTokens, provider: cloudProvider)
    }
    
    public func executeTask(prompt: String, session: Session) async throws {
        await session.updateStatus(.thinking)
        onStatusUpdate?(.working)
        
        // Sound Architect: Dampen background audio (FoleyDimmerLogic)
        await AudioArchitect.shared.dampen()
        
        // 1. Cognitive Simulation (Internal Monologue)
        let ragContext = await memory.retrieveRelevantExperiences(query: prompt)
        onStepUpdate?(TaskStep(name: "Simulating strategies...", status: "thinking", latency: "...", depth: session.recursionDepth))
        
        if let strategy = try? await InternalMonologueActor.shared.simulate(task: prompt, context: ragContext, provider: cloudProvider) {
            onStepUpdate?(TaskStep(name: "Strategy: \(strategy.name)", status: "done", latency: "ANE", depth: session.recursionDepth, thought: "Plan: \(strategy.plan)\nRisk: \(strategy.risk)"))
        }

        await contextManager.addMessage(Message(role: "user", content: prompt))
        var isRunning = true
        
        while isRunning {
            // 1. Check Recursion Depth
            if await session.isRecursionLimitReached() {
                await session.updateStatus(.failed)
                throw NSError(domain: "Orchestrator", code: 4, userInfo: [NSLocalizedDescriptionKey: "Max recursion depth reached"])
            }
            
            // 2. RAG Retrieval
            let ragContext = await memory.retrieveRelevantExperiences(query: prompt)
            
            // 3. Get Next Move from Planner
            let systemPrompt = await PlannerTemplate.generateAgenticPrompt(session: session, ragContext: ragContext)
            
            // Memory Compression: Check if context is too large
            try? await contextManager.compress(sessionID: session.id.uuidString)
            
            let request = CompletionRequest(
                taskID: session.id.uuidString,
                systemPrompt: systemPrompt,
                messages: await contextManager.getMessages(),
                maxTokens: 2000,
                sensitivityLevel: .public,
                complexity: 3
            )
            
            let response = try await cloudProvider.complete(request)
            await contextManager.addMessage(Message(role: "assistant", content: response.content))
            await session.addTokenUsage(response.tokensUsed.total)
            
            // 3. Parse Thinking vs Action
            let result = ThinkingParser.parse(response.content)
            
            // Log thinking (we'll need a callback or signal to the UI Orchestrator)
            // For now, print it
            if let think = result.thinking {
                let depth = session.recursionDepth
                onStepUpdate?(TaskStep(name: "Reasoning...", status: "thinking", latency: "...", depth: depth, thought: think))
            }
            
            // 4. Determine Action
            if let toolCall = parseToolCall(result.finalAnswer) {
                let depth = session.recursionDepth
                onStepUpdate?(TaskStep(name: "Tool: \(toolCall.name)", status: "executing", latency: "...", depth: depth))
                
                await session.updateStatus(.executing)
                
                if let tool = toolRegistry.getTool(named: toolCall.name) {
                    do {
                        // Safety Check (LogicGate)
                        if toolCall.name == "shell_exec", let cmd = toolCall.params["command"]?.value as? String {
                            let risk = LogicGate.shared.check(command: cmd)
                            if risk.isDangerous {
                                throw ToolError.executionError("Safety Block: \(risk.reason ?? "Dangerous command detected")")
                            }
                        }
                        
                        let toolResult = try await tool.execute(params: toolCall.params, session: session)
                        await contextManager.addMessage(Message(role: "user", content: "Tool [\(toolCall.name)] returned: \(toolResult)"))
                    } catch {
                        // Self-Healing Logic (Autonomous Recovery)
                        if let strategy = await SelfHealingEngine.shared.analyze(error: error.localizedDescription, tool: toolCall.name),
                           await SelfHealingEngine.shared.canRetry(error: error.localizedDescription) {
                            
                            onStepUpdate?(TaskStep(name: "Healing: \(strategy.name)", status: "healing", latency: "Retry", depth: session.recursionDepth, thought: strategy.description))
                            await session.updateStatus(.healing)
                            onStatusUpdate?(.healing)
                            await session.recordHealingAttempt()
                            await SelfHealingEngine.shared.recordRetry(error: error.localizedDescription)
                            
                            // Execute healing command if it exists
                            if let fixCmd = strategy.command {
                                _ = try? await (toolRegistry.getTool(named: "shell_exec")?.execute(params: ["command": AnyCodable(fixCmd)], session: session))
                            }
                            
                            await contextManager.addMessage(Message(role: "user", content: "Tool [\(toolCall.name)] failed but I applied healing: \(strategy.name). Retrying..."))
                            onStatusUpdate?(.working)
                        } else {
                            await contextManager.addMessage(Message(role: "user", content: "Tool [\(toolCall.name)] failed with error: \(error.localizedDescription)"))
                        }
                    }
                } else {
                    await contextManager.addMessage(Message(role: "user", content: "Tool [\(toolCall.name)] not found in registry."))
                }
            } else {
                // No tool call found, assume it's the final answer
                await session.updateStatus(.finished, finalAnswer: result.finalAnswer)
                isRunning = false
                
                // 5. Store Experience (Cumulative Intelligence)
                await memory.storeExperience(task: prompt, solution: result.finalAnswer)
                
                // Sound Architect: Restore background audio (FoleyDimmerLogic)
                await AudioArchitect.shared.restore()
                
                print("[FINAL]: \(result.finalAnswer)")
            }
        }
    }
    
    private struct ToolCall: Decodable {
        let name: String
        let params: [String: AnyCodable]
        
        enum CodingKeys: String, CodingKey {
            case tool = "tool"
            case params = "params"
        }
        
        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            name = try container.decode(String.self, forKey: .tool)
            params = try container.decode([String: AnyCodable].self, forKey: .params)
        }
    }
    
    private func parseToolCall(_ text: String) -> (name: String, params: [String: AnyCodable])? {
        // Simple JSON extractor for tool calls
        guard let start = text.firstIndex(of: "{"), let end = text.lastIndex(of: "}") else { return nil }
        let jsonStr = String(text[start...end])
        
        guard let data = jsonStr.data(using: .utf8),
              let toolCall = try? JSONDecoder().decode(ToolCall.self, from: data) else {
            return nil
        }
        
        return (toolCall.name, toolCall.params)
    }
}
