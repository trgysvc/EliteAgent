import Foundation

// v14.7: Lightweight Plugin Interface for Recursive Evolution.
// This file is standalone and has ZERO dependencies (only Foundation).
// It allows PluginCraft to compile plugins without linking to the full EliteAgentCore.

public struct AnyCodable: Codable, Sendable {
    public let value: Any
    
    public init(_ value: Any) {
        self.value = value
    }
    
    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let v = try? container.decode(String.self) { value = v }
        else if let v = try? container.decode(Int.self) { value = v }
        else if let v = try? container.decode(Double.self) { value = v }
        else if let v = try? container.decode(Bool.self) { value = v }
        else { value = "" }
    }
    
    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        if let v = value as? String { try container.encode(v) }
        else if let v = value as? Int { try container.encode(v) }
        else if let v = value as? Double { try container.encode(v) }
        else if let v = value as? Bool { try container.encode(v) }
    }
}

public struct UNOToolSignature: Codable, Sendable {
    public let id: String
    public let name: String
    public let summary: String
    public let description: String
    public let ubid: Int
    
    public init(id: String, name: String, summary: String, description: String, ubid: Int) {
        self.id = id
        self.name = name
        self.summary = summary
        self.description = description
        self.ubid = ubid
    }
}

public struct UNOActionWrapper: Codable, Sendable {
    public let toolID: String
    public let params: [String: AnyCodable]
    public let version: Int = 1
}

public struct UNOResponse: Codable, Sendable {
    public let result: String
    public let error: String?
    
    public init(result: String, error: String? = nil) {
        self.result = result
        self.error = error
    }
}

public protocol UNOToolPlugin: AnyObject, Sendable {
    var signature: UNOToolSignature { get }
    func execute(action: UNOActionWrapper) async throws -> UNOResponse
}
