import Foundation

public struct LLMOutput: Sendable {
    public let text: String
    public let thinkBlock: String?
    public let tokenCount: TokenCount
    public let latencyMs: Int
    
    public init(text: String, thinkBlock: String?, tokenCount: TokenCount, latencyMs: Int) {
        self.text = text
        self.thinkBlock = thinkBlock
        self.tokenCount = tokenCount
        self.latencyMs = latencyMs
    }
}

/// Placeholder for the actual MLX Model handling logic.
/// MLX arrays and model weights are managed here.
public actor LLMModel {
    public static func load(_ name: String) async throws -> LLMModel {
        // Loads MLX weights from file system and initializes the specific architecture
        return LLMModel()
    }
    
    public func generate(systemPrompt: String, messages: [Message], maxTokens: Int, temperature: Double) async throws -> LLMOutput {
        // Simulate a raw string output from the LLM containing a think block
        let dummyRawOutput = "<think>\nThinking process...\n</think>\nFinal Answer."
        
        let parsed = Self.parseThinkBlock(from: dummyRawOutput)
        
        return LLMOutput(
            text: parsed.content,
            thinkBlock: parsed.think,
            tokenCount: TokenCount(prompt: 10, completion: 20, total: 30),
            latencyMs: 1500
        )
    }
    
    /// Parses `<think>` tags conforming to PRD Madde 6.4 requirement for R1-32B support
    public static func parseThinkBlock(from text: String) -> (think: String?, content: String) {
        let pattern = "(?s)<think>(.*?)</think>\\s*(.*)"
        guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else {
            return (nil, text)
        }
        
        let nsRange = NSRange(text.startIndex..<text.endIndex, in: text)
        guard let match = regex.firstMatch(in: text, options: [], range: nsRange) else {
            return (nil, text)
        }
        
        let thinkRange = Range(match.range(at: 1), in: text)
        let contentRange = Range(match.range(at: 2), in: text)
        
        var thinkStr: String? = nil
        if let r = thinkRange {
            thinkStr = String(text[r]).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        
        var contentStr = text
        if let r = contentRange {
            contentStr = String(text[r]).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        
        return (thinkStr, contentStr)
    }
}
