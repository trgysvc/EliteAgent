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
    private var ubidMap: [Int: any AgentTool] = [:] // v13.8: Binary ID Map
    private var statusMap: [String: ToolStatus] = [:]
    
    public init() {}
    
    public func register(_ tool: any AgentTool) {
        queue.async(flags: .barrier) {
            self.tools[tool.name] = tool
            self.ubidMap[tool.ubid] = tool
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
    
    public func getTool(ubid: Int) -> (any AgentTool)? {
        queue.sync {
            return ubidMap[ubid]
        }
    }
    
    public func getToolIndices() -> [Int] {
        queue.sync {
            return Array(ubidMap.keys)
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
        let tool: any AgentTool
        
        // v13.8: Direct UBID Lookup (UNO Pure)
        if let ubid = toolCall.ubid, let t = getTool(ubid: ubid) {
            tool = t
        } else if let t = getTool(named: toolCall.tool) {
            tool = t
        } else {
            // v11.9: Smart Feedback for miscalled sub-actions
            let miscalledActions = ["play_content", "volume", "pause", "play", "next", "stop"]
            if miscalledActions.contains(toolCall.tool) {
                throw ToolError.executionError("Tool not found: \(toolCall.tool). LÜTFEN DİKKAT: '\(toolCall.tool)' bağımsız bir araç değildir, 'media_control' aracının bir aksiyonudur. Doğru kullanım: CALL([18]) WITH {\"action\": \"\(toolCall.tool)\", ...}")
            }
            throw ToolError.executionError("Tool not found: \(toolCall.tool) / UBID \(toolCall.ubid ?? 0)")
        }
        
        updateStatus(named: tool.name) { $0.callCount += 1 }
        
        do {
            // v16.2: Global Parameter Normalization
            // If the model hallucinates 'param' instead of 'action', normalize it here 
            // to protect all tools from SLM-specific calling slips.
            var normalizedParams = toolCall.params
            if normalizedParams["action"] == nil, let paramValue = normalizedParams["param"] {
                normalizedParams["action"] = paramValue
            }
            
            // v10.5.5: Full Transparency - Log Dispatch
            AgentLogger.logAudit(level: .info, agent: "ToolRegistry", message: "🛠 Executing Tool: \(tool.name) | Params: \(normalizedParams)")
            
            let result = try await tool.execute(params: normalizedParams, session: session)
            
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
