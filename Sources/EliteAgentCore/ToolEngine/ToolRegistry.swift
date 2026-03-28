import Foundation

public final class ToolRegistry {
    public static let shared = ToolRegistry()
    
    private let queue = DispatchQueue(label: "com.eliteagent.toolregistry", attributes: .concurrent)
    private var tools: [String: any AgentTool] = [:]
    
    public init() {}
    
    public func register(_ tool: any AgentTool) {
        queue.async(flags: .barrier) {
            self.tools[tool.name] = tool
        }
    }
    
    public func getTool(named name: String) -> (any AgentTool)? {
        queue.sync {
            return tools[name]
        }
    }
    
    public func listTools() -> [any AgentTool] {
        queue.sync {
            return Array(tools.values)
        }
    }
}

extension ToolRegistry: @unchecked Sendable {}
