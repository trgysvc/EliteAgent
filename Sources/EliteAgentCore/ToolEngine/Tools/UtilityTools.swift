import Foundation

public struct UtilityTools: Sendable {
    public init() {}
    
    /// UNO Pure: Bridges a text-based structured payload into an internal dictionary or key-path result.
    public func structureParse(data: Data, keyPath: String? = nil) throws -> String {
        // v13.8: UNO Pure - Delegate parsing to shielded bridge
        guard let dict = UNOExternalBridge.resolveDictionary(from: data) else {
            return String(data: data, encoding: .utf8) ?? ""
        }
        
        if let path = keyPath, !path.isEmpty {
            let keys = path.split(separator: ".")
            var current: Any = dict
            
            for key in keys {
                if let mapped = current as? [String: Any], let next = mapped[String(key)] {
                    current = next
                } else {
                    return "Key path \(path) not found."
                }
            }
            
            // v13.8: UNO Pure - Delegate re-encoding to shielded bridge
            guard let resultData = UNOExternalBridge.prepareExternalBlob(from: ["result": current]) else {
                return "Protocol mapping failed."
            }
            return String(data: resultData, encoding: .utf8) ?? ""
        }
        
        // v13.8: UNO Pure - Delegate re-encoding to shielded bridge
        guard let resultData = UNOExternalBridge.prepareExternalBlob(from: dict) else {
            return "Protocol mapping failed."
        }
        return String(data: resultData, encoding: .utf8) ?? ""
    }
    
    public func grep(pattern: String, in text: String) throws -> [String] {
        let regex = try NSRegularExpression(pattern: pattern)
        let matches = regex.matches(in: text, range: NSRange(text.startIndex..., in: text))
        
        return matches.compactMap { match in
            if let range = Range(match.range, in: text) {
                return String(text[range])
            }
            return nil
        }
    }
    
    public func summarize(text: String, using provider: any LLMProvider) async throws -> String {
        let req = CompletionRequest(
            taskID: UUID().uuidString,
            systemPrompt: "You are a specialized summarization agent. Summarize the user's provided text comprehensively.",
            messages: [Message(role: "user", content: text)],
            maxTokens: 500,
            sensitivityLevel: .public,
            complexity: 2
        )
        let res = try await provider.complete(req, useSafeMode: false)
        return res.content
    }
}
