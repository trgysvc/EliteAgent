import Foundation

/// v13.7: Unified Tool Signature for LLM discovery.
/// Defines how a tool (Native or Dynamic Plugin) describes itself to the model.
/// MCP compatible schema structure for future system integration.
public struct UNOToolSignature: Codable, Sendable {
    public let id: String
    public let name: String            // Slug-name (e.g. xcode_build)
    public let summary: String         // One-liner for fast discovery
    public let description: String     // Detailed instructions for LLM
    public let ubid: Int               // Unique Binary ID for logic-level tokenization
    public let parameterSchema: [String: AnyCodable] // MCP/Binary-Schema fragment
    public let requiredParameters: [String]
    
    public init(id: String, name: String, summary: String, description: String, ubid: Int, parameterSchema: [String: AnyCodable] = [:], requiredParameters: [String] = []) {
        self.id = id
        self.name = name
        self.summary = summary
        self.description = description
        self.ubid = ubid
        self.parameterSchema = parameterSchema
        self.requiredParameters = requiredParameters
    }
}

/// The protocol all dynamic plugins must conform to.
/// Plugins are stored as .dylib/.bundle files in ~/Library/Application Support/EliteAgent/Plugins
public protocol UNOToolPlugin: AnyObject, Sendable {
    var signature: UNOToolSignature { get }
    func execute(action: UNOActionWrapper) async throws -> UNOResponse
}

/// v13.7: Bridge extension to convert legacy AgentTools to UNOToolSignatures
extension AgentTool {
    public var unoSignature: UNOToolSignature {
        return UNOToolSignature(
            id: self.name,
            name: self.name,
            summary: self.summary,
            description: self.description,
            ubid: self.ubid
        )
    }
}
