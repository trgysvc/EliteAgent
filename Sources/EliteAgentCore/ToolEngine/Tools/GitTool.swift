import Foundation

public struct GitTool: AgentTool, Sendable {
    public let name = "git_action"
    public let summary = "Manage Git commits, reverts, and diffs."
    public let description = "Executes git operations (commit, revert, status, diff) via GitStateEngine. Provide 'path' to explicitly set the active Git repository directory."
    public let ubid: Int128 = 42 // Token 'K' in Qwen 2.5
    
    public init() {}
    
    public func execute(params: [String: AnyCodable], session: Session) async throws(AgentToolError) -> String {
        guard let action = params["action"]?.value as? String else {
            throw AgentToolError.missingParameter("action")
        }
        
        if let path = params["path"]?.value as? String {
            await GitStateEngine.shared.setProjectRoot(path)
        }
        
        let engine = GitStateEngine.shared
        
        do {
            switch action {
            case "commit":
                guard let message = params["message"]?.value as? String else {
                    throw AgentToolError.missingParameter("message")
                }
                try await engine.commit(message: message)
                return "SUCCESS: Changes committed with message: '\(message)'"
                
            case "revert":
                guard let hash = params["hash"]?.value as? String else {
                    throw AgentToolError.missingParameter("hash")
                }
                try await engine.revert(to: hash)
                return "SUCCESS: Reverted working directory to hash \(hash)"
                
            case "status":
                let status = try await engine.status()
                return status.isEmpty ? "No changes in working directory." : status
                
            case "diff":
                let diff = try await engine.diff()
                return diff.isEmpty ? "No unstaged changes." : diff
                
            default:
                throw AgentToolError.executionError("Unsupported git action: \(action)")
            }
        } catch {
            if let toolError = error as? AgentToolError {
                throw toolError
            }
            throw AgentToolError.executionError(error.localizedDescription)
        }
    }
}
