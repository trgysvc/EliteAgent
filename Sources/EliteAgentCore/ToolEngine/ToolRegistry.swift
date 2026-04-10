import Foundation

public struct ToolStatus: Codable, Sendable {
    public var isAvailable: Bool = true
    public var lastError: String?
    public var callCount: Int = 0
    public var crashCount: Int = 0
    
    public init(isAvailable: Bool = true, lastError: String? = nil, callCount: Int = 0, crashCount: Int = 0) {
        self.isAvailable = isAvailable
        self.lastError = lastError
        self.callCount = callCount
        self.crashCount = crashCount
    }
}

public final class ToolRegistry {
    public static let shared = ToolRegistry()
    
    private let queue = DispatchQueue(label: "com.eliteagent.toolregistry", attributes: .concurrent)
    private var tools: [String: any AgentTool] = [:]
    private var statusMap: [String: ToolStatus] = [:]
    
    public init() {}
    
    public func register(_ tool: any AgentTool) {
        queue.async(flags: .barrier) {
            self.tools[tool.name] = tool
            if self.statusMap[tool.name] == nil {
                self.statusMap[tool.name] = ToolStatus()
            }
        }
    }
    
    public func getToolStatus(named name: String) -> ToolStatus {
        queue.sync {
            return statusMap[name] ?? ToolStatus()
        }
    }
    
    public func updateStatus(named name: String, block: @escaping @Sendable (inout ToolStatus) -> Void) {
        queue.async(flags: .barrier) {
            var status = self.statusMap[name] ?? ToolStatus()
            block(&status)
            self.statusMap[name] = status
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
    
    public func getHealthyTools() -> [any AgentTool] {
        queue.sync {
            return tools.values.filter { tool in
                statusMap[tool.name]?.isAvailable ?? true
            }
        }
    }
    
    public func execute(toolCall: ToolCall, session: Session) async throws -> String {
        guard let tool = getTool(named: toolCall.tool) else {
            // v11.9: Smart Feedback for miscalled sub-actions
            let miscalledActions = ["play_content", "volume", "pause", "play", "next", "stop"]
            if miscalledActions.contains(toolCall.tool) {
                throw ToolError.executionError("Tool not found: \(toolCall.tool). LÜTFEN DİKKAT: '\(toolCall.tool)' bağımsız bir araç değildir, 'media_control' aracının bir aksiyonudur. Doğru kullanım: {\"toolID\": \"media_control\", \"params\": {\"action\": \"\(toolCall.tool)\", ...}}")
            }
            throw ToolError.executionError("Tool not found: \(toolCall.tool)")
        }
        
        updateStatus(named: tool.name) { $0.callCount += 1 }
        
        do {
            // v10.5.5: Full Transparency - Log Dispatch
            AgentLogger.logAudit(level: .info, agent: "ToolRegistry", message: "🛠 Executing Tool: \(tool.name) | Params: \(toolCall.params)")
            
            let result = try await tool.execute(params: toolCall.params, session: session)
            
            // v10.5.5: Full Transparency - Log Result Size
            AgentLogger.logAudit(level: .info, agent: "ToolRegistry", message: "✅ Tool Result: \(tool.name) | Output Size: \(result.count) chars")
            
            // Reset crash count on success if it was healthy
            updateStatus(named: tool.name) { status in
                if status.crashCount < 3 { status.crashCount = 0 }
                status.lastError = nil
            }
            return result
        } catch {
            // v10.5.5: Full Transparency - Log Error
            AgentLogger.logAudit(level: .error, agent: "ToolRegistry", message: "❌ Tool Error: \(tool.name) | Error: \(error.localizedDescription)")
            
            updateStatus(named: tool.name) { status in
                status.crashCount += 1
                status.lastError = error.localizedDescription
                if status.crashCount >= 3 {
                    status.isAvailable = false
                }
            }
            throw error
        }
    }
}

extension ToolRegistry: @unchecked Sendable {}
