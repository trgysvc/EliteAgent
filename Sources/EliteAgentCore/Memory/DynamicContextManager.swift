import Foundation

public actor DynamicContextManager {
    private var messages: [Message] = []
    private let maxTokens: Int
    private let threshold: Double = 0.8
    private weak var provider: CloudProvider?
    
    public init(maxTokens: Int, provider: CloudProvider) {
        self.maxTokens = maxTokens
        self.provider = provider
    }
    
    public func addMessage(_ message: Message) {
        messages.append(message)
    }
    
    public func getMessages() -> [Message] {
        return messages
    }
    
    public func compress(sessionID: String) async throws {
        // Simple estimation: 4 chars per token if no real count
        let totalChars = messages.reduce(0) { $0 + ($1.content.count) }
        let estimatedTokens = totalChars / 4
        
        guard Double(estimatedTokens) > Double(maxTokens) * threshold else { return }
        
        // Summarize logic (Phase 1 recursive summarization)
        // Keep: Initial System Prompt (index 0), Goal (index 1), and last 5 messages.
        guard messages.count > 10 else { return }
        
        let immutableHead = Array(messages.prefix(2))
        let tail = Array(messages.suffix(5))
        let middle = Array(messages[2..<(messages.count - 5)])
        
        let middleText = middle.map { "[\($0.role)]: \($0.content)" }.joined(separator: "\n")
        
        // Ask provider for a summary of the middle part
        if let provider = provider {
            let summaryRequest = CompletionRequest(
                taskID: sessionID,
                systemPrompt: "Önceki konuşmalarının özetini çıkart. Teknik detayları ve ulaşılan sonuçları koru.",
                messages: [Message(role: "user", content: "Şu konuşma geçmişini teknik bir özet haline getir:\n\n\(middleText)")],
                maxTokens: 500,
                sensitivityLevel: .public,
                complexity: 2
            )
            
            let response = try await provider.complete(summaryRequest)
            let summaryMessage = Message(role: "system", content: "### GEÇMİŞ ÖZETİ (HISTORICAL SUMMARY):\n\(response.content)")
            
            self.messages = immutableHead + [summaryMessage] + tail
            print("[MEMORY]: Context compressed. Tokens estimated: \(estimatedTokens)")
        }
    }
    
    public func clear() {
        messages.removeAll()
    }
}
