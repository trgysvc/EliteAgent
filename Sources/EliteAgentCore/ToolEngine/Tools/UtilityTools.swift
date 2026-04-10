import Foundation

public struct UtilityTools: Sendable {
    public init() {}
    
    public func jsonParse(data: Data, keyPath: String? = nil) throws -> String {
        guard let dict = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
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
            
            let resultData = try JSONSerialization.data(withJSONObject: current, options: .prettyPrinted)
            return String(data: resultData, encoding: .utf8) ?? ""
        }
        
        let resultData = try JSONSerialization.data(withJSONObject: dict, options: .prettyPrinted)
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
