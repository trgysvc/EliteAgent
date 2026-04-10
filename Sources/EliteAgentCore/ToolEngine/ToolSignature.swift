import Foundation

/// v13.7: Unified Tool Signature for LLM discovery.
/// Defines how a tool (Native or Dynamic Plugin) describes itself to the model.
public struct UNOToolSignature: Codable, Sendable {
    public let id: String
    public let name: String
    public let description: String
    public let schema: [String: AnyCodable] // JSON Schema or GBNF fragment
    
    public init(id: String, name: String, description: String, schema: [String: AnyCodable]) {
        self.id = id
        self.name = name
        self.description = description
        self.schema = schema
    }
}

/// The protocol all dynamic plugins must conform to.
/// Plugins are stored as .bundle files in ~/Library/Application Support/EliteAgent/Plugins
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
            description: self.description,
            schema: [:] // TODO: Implement automatic schema extraction from legacy tools
        )
    }
}
