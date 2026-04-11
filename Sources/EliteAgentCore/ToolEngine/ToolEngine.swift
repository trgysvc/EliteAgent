import Foundation

public struct ParamDefinition: Codable, Sendable {
    public let type: String
    public let description: String
    public let required: Bool
    
    public init(type: String, description: String, required: Bool) {
        self.type = type
        self.description = description
        self.required = required
    }
}

public struct ToolDefinition: Codable, Sendable {
    public let toolID: String
    public let description: String
    public let category: ToolCategory
    public let requiresSandbox: Bool
    public let requiresApproval: Bool
    public let requiresPrivacyCheck: Bool
    public let params: [String: ParamDefinition]
    public let handlerClass: String
    
    public enum ToolCategory: String, Codable, Sendable {
        case filesystem, system, network, data, mcp, cua
    }
}

public actor ToolEngine {
    public private(set) var tools: [String: ToolDefinition] = [:]
    
    public init() {}
    
    public func loadTools(from directory: URL) throws {
        guard FileManager.default.fileExists(atPath: directory.path) else { return }
        let urls = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
        
        // v13.8: Using PropertyListDecoder for UNO Pure (No JSON Artıkları)
        let decoder = PropertyListDecoder()
        var newTools = [String: ToolDefinition]()
        
        for url in urls where url.pathExtension == "plist" {
            let data = try Data(contentsOf: url)
            let tool = try decoder.decode(ToolDefinition.self, from: data)
            newTools[tool.toolID] = tool
        }
        
        self.tools = newTools
    }
}
