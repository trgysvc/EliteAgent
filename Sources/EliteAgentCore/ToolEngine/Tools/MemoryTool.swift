import Foundation

public struct MemoryTool: AgentTool, Sendable {
    public let name = "memory"
    public let summary = "Search/Store long-term cognitive data."
    public let description = "Searches or saves persistent architectural memories using MemoryAgent. Actions: search (query), save (task, solution)."
    public let ubid = 44 // Token 'M' in Qwen 2.5
    
    private let agent: MemoryAgent
    
    public init(agent: MemoryAgent) {
        self.agent = agent
    }
    
    public func execute(params: [String: AnyCodable], session: Session) async throws -> String {
        guard let action = params["action"]?.value as? String else {
            throw ToolError.missingParameter("action")
        }
        
        switch action {
        case "search":
            guard let query = params["query"]?.value as? String else {
                throw ToolError.missingParameter("query")
            }
            let result = await agent.retrieveRelevantExperiences(query: query)
            return result.isEmpty ? "No internal experiences found." : result
            
        case "save":
            // Fallback: if 'query' is provided instead of 'task' and 'solution'
            let task = (params["task"]?.value as? String) ?? "Auto-Saved Memory/Strategy"
            let solution = (params["solution"]?.value as? String) ?? (params["query"]?.value as? String) ?? ""
            
            if solution.isEmpty {
                throw ToolError.missingParameter("task/solution or query (Required for save)")
            }
            
            await agent.storeExperience(task: task, solution: solution)
            return "SUCCESS: Experience stored in long-term memory."
            
        default:
            throw ToolError.executionError("Unsupported memory action: \(action)")
        }
    }
}
