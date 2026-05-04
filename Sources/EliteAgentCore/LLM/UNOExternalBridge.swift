import Foundation

/// UNO Pure: External Protocol Isolation Bridge
/// This is the ONLY file in the EliteAgent codebase permitted to interact with JSON structures.
/// It acts as a shielded adaptor for external network protocols (OpenAI, OpenRouter, MCP, HF Manifests).
/// Internal logic MUST NOT call JSON utilities directly; they must use this bridge's abstract binary interfaces.
public enum UNOExternalBridge {
    
    // MARK: - Network Payload Preparation
    
    /// Encodes a dictionary to binary data formatted for external HTTP JSON APIs.
    public static func encodeExternalPayload(_ dict: [String: Any]) throws -> Data {
        // v13.8: Shielded Serialization
        return try JSONSerialization.data(withJSONObject: dict)
    }
    
    /// Decodes binary data from an external API into a dictionary.
    public static func decodeExternalResponse(_ data: Data) throws -> [String: Any] {
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw BridgeError.invalidFormat("External response is not a valid dictionary.")
        }
        return json
    }
    
    // MARK: - Model Manifest Discovery
    
    /// Extracts architecture info from a HuggingFace-standard config.json without exposing JSON logic to the engine.
    public static func resolveArchitectures(from data: Data) -> [String] {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let architectures = json["architectures"] as? [String] else {
            return []
        }
        return architectures
    }
    
    // MARK: - Specialized Decoders
    
    /// Specialized decoder for OpenAI-compatible chat responses.
    public static func parseCloudResponse(data: Data) throws -> (text: String, think: String?, tokens: (prompt: Int, completion: Int, total: Int)) {
        // We use a private struct here to keep it isolated from the rest of the app's type system.
        struct InternalResponse: Codable {
            struct Choice: Codable {
                struct Message: Codable {
                    let content: String?
                    let reasoning: String?
                }
                let message: Message
            }
            struct Usage: Codable {
                let prompt_tokens: Int?
                let completion_tokens: Int?
                let total_tokens: Int?
            }
            let choices: [Choice]
            let usage: Usage?
        }
        
        let decoded = try JSONDecoder().decode(InternalResponse.self, from: data)
        guard let choice = decoded.choices.first else { throw BridgeError.emptyResponse }
        
        let text = choice.message.content ?? ""
        let think = choice.message.reasoning
        let usage = (
            prompt: decoded.usage?.prompt_tokens ?? 0,
            completion: decoded.usage?.completion_tokens ?? 0,
            total: decoded.usage?.total_tokens ?? 0
        )
        
        return (text, think, usage)
    }
    
    // MARK: - Tokenizer Manifest
    
    /// UNO Pure: Bridges a tokenizer.json file into a native vocabulary and merges map.
    public static func loadTokenizerManifest(data: Data) -> (vocab: [String: Int], merges: [String: Int]) {
        struct TokenizerFile: Codable {
            struct Model: Codable {
                let vocab: [String: Int]
                let merges: [String]?
            }
            let model: Model
        }
        
        guard let decoded = try? JSONDecoder().decode(TokenizerFile.self, from: data) else {
            return ([:], [:])
        }
        
        var mergeMap = [String: Int]()
        if let merges = decoded.model.merges {
            for (index, merge) in merges.enumerated() {
                mergeMap[merge] = index
            }
        }
        
        return (decoded.model.vocab, mergeMap)
    }
    
    // MARK: - JSON-RPC 2.0 (MCP Support)
    
    public struct ExternalJSONRPCRequest: Codable {
        public var jsonrpc = "2.0"
        public let id: String
        public let method: String
        public let params: [String: String]?
    }
    
    public struct ExternalJSONRPCResponse: Codable {
        public let jsonrpc: String
        public let id: String
        public let result: [String: String]?
        public let error: [String: String]?
    }
    
    public static func encodeJSONRPCRequest(id: String, method: String, params: [String: String]? = nil) -> Data? {
        let req = ExternalJSONRPCRequest(id: id, method: method, params: params)
        return try? JSONEncoder().encode(req)
    }
    
    public static func decodeJSONRPCResponse(data: Data) -> (id: String, result: [String: String]?, error: [String: String]?)? {
        guard let res = try? JSONDecoder().decode(ExternalJSONRPCResponse.self, from: data) else { return nil }
        return (res.id, res.result, res.error)
    }
    
    // MARK: - Generic Support (UI & Tools Bridge)
    
    /// UNO Pure: Bridges a raw text block into a dictionary for internal Swift 6 use.
    public static func resolveDictionary(from data: Data) -> [String: Any]? {
        return try? JSONSerialization.jsonObject(with: data) as? [String: Any]
    }
    
    /// UNO Pure: Bridges a dictionary into a binary blob for external consumption.
    public static func prepareExternalBlob(from dict: [String: Any]) -> Data? {
        return try? JSONSerialization.data(withJSONObject: dict)
    }
    
    /// UNO Pure: Bridges binary action parameters from the LLM signal into a native dictionary.
    public static func resolveActionParameters(from text: String) -> [String: Any]? {
        guard let data = text.data(using: .utf8) else { return nil }
        return try? JSONSerialization.jsonObject(with: data) as? [String: Any]
    }
    
    /// UNO Pure: Specialized Decodable bridge for UI Models.
    public static func decodeDecodable<T: Decodable>(_ type: T.Type, from data: Data) -> T? {
        return try? JSONDecoder().decode(T.self, from: data)
    }

    /// UNO Pure: Encodes an Encodable type for an external HTTP JSON API.
    public static func encodeEncodable<T: Encodable>(_ value: T) -> Data? {
        return try? JSONEncoder().encode(value)
    }

    /// UNO Pure: Decodes an Encodable type from external HTTP JSON data.
    public static func decodeExternalDecodable<T: Decodable>(_ type: T.Type, from data: Data) throws -> T {
        return try JSONDecoder().decode(type, from: data)
    }
}

public enum BridgeError: Error, LocalizedError {
    case invalidFormat(String)
    case emptyResponse
    
    public var errorDescription: String? {
        switch self {
        case .invalidFormat(let m): return m
        case .emptyResponse: return "Harici servis boş yanıt döndürdü."
        }
    }
}
