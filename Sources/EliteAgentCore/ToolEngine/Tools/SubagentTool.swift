import Foundation

public struct SubagentTool: AgentTool, Sendable {
    public let name = "subagent_spawn"
    public let summary = "Recursive spawning for complex sub-tasks."
    public let description = "Spawn a sub-agent to handle a specific sub-task."
    public let ubid: Int128 = 19 // Token '4' in Qwen 2.5
    
    private let runtimeCreator: @Sendable (PlannerAgent, CloudProvider) -> OrchestratorRuntime
    private let planner: PlannerAgent
    private let cloudProvider: CloudProvider
    private let onStepUpdate: (@Sendable (TaskStep) -> Void)?
    
    public init(planner: PlannerAgent, 
                cloudProvider: CloudProvider, 
                onStepUpdate: (@Sendable (TaskStep) -> Void)? = nil,
                runtimeCreator: @escaping @Sendable (PlannerAgent, CloudProvider) -> OrchestratorRuntime) {
        self.planner = planner
        self.cloudProvider = cloudProvider
        self.onStepUpdate = onStepUpdate
        self.runtimeCreator = runtimeCreator
    }
    
    public func execute(params: [String: AnyCodable], session: Session) async throws(AgentToolError) -> String {
        guard let prompt = params["prompt"]?.value as? String else {
            throw AgentToolError.missingParameter("prompt")
        }
        
        let childSession = Session(
            parentID: session.id,
            recursionDepth: session.recursionDepth + 1,
            maxRecursionDepth: session.maxRecursionDepth,
            workspaceURL: session.workspaceURL
        )
        
        let runtime = runtimeCreator(planner, cloudProvider)
        let subagentID = UUID()
        await SubagentRegistry.shared.register(id: subagentID, runtime: runtime)
        
        if let handler = onStepUpdate {
            await runtime.setStepUpdateHandler(handler)
        }
        
        let config = session.config
        let complexity = session.complexity
        
        do {
            defer {
                Task { await SubagentRegistry.shared.unregister(id: subagentID) }
            }
            try await runtime.executeTask(
                prompt: prompt, 
                session: childSession, 
                complexity: complexity, 
                config: config
            )
            return "Subagent task completed. (Depth: \(childSession.recursionDepth))"
        } catch {
            throw AgentToolError.executionError("Subagent execution failed: \(error.localizedDescription)")
        }
    }
}
