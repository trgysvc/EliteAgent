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
        // via the dedicated InferenceActor (Titan Core)
        try await InferenceActor.shared.loadModel(at: URL(fileURLWithPath: "/models/\(name)"))
        return LLMModel()
    }
    
    public func generate(systemPrompt: String, messages: [Message], maxTokens: Int, temperature: Double) async throws -> LLMOutput {
        let startTime = Date()
        
        // Execute real-time reasoning via the InferenceActor (Neural Sight & SLM)
        let stream = await InferenceActor.shared.generate(messages: messages, maxTokens: maxTokens)
        var fullResponse = ""
        
        for await token in stream {
            fullResponse += token
        }
        
        let endTime = Date()
        let latencyMs = Int(endTime.timeIntervalSince(startTime) * 1000)
        
        // v11.0: Real latency and calibrated character-based token estimation (BPE approximation)
        let promptChars = messages.map { $0.content.count }.reduce(0, +)
        let completionChars = fullResponse.count
        
        return LLMOutput(
            text: fullResponse,
            thinkBlock: "Local Titan reasoning completed (MLX Engine).",
            tokenCount: TokenCount(
                prompt: Int(Double(promptChars) / 4.0), 
                completion: Int(Double(completionChars) / 4.0), 
                total: Int(Double(promptChars + completionChars) / 4.0)
            ),
            latencyMs: max(latencyMs, 1)
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
