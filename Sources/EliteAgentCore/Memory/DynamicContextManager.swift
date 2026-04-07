import Foundation
import OSLog

/// A hardened context manager for managing conversation history.
/// Implements 'autoCompact' and 'compactBoundary' strategies for EliteAgent v10.0.
public actor DynamicContextManager {
    private var messages: [Message] = []
    private let maxTokens: Int
    private let threshold: Double = 0.8
    private weak var provider: CloudProvider?
    
    /// The index after which messages are considered 'recent' and protected from summarization.
    private var compactBoundary: Int = 10
    
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
    
    /// Updates the boundary for protection.
    public func setCompactBoundary(_ index: Int) {
        self.compactBoundary = index
    }
    
    /// v10.0: Intelligent Context Compaction (autoCompact)
    public func compress(sessionID: String) async throws {
        let totalChars = messages.reduce(0) { $0 + ($1.content.count) }
        let estimatedTokens = totalChars / 4
        
        guard Double(estimatedTokens) > Double(maxTokens) * threshold else { return }
        
        // Strategy: 
        // 1. Keep System Prompt (0) and Initial Goal (1)
        // 2. Summarize everything between index 2 and (messages.count - compactBoundary)
        // 3. Keep the last 'compactBoundary' messages as is.
        
        guard messages.count > (compactBoundary + 5) else { return }
        
        let immutableHead = Array(messages.prefix(2))
        let tail = Array(messages.suffix(compactBoundary))
        let middle = Array(messages[2..<(messages.count - compactBoundary)])
        
        let middleText = middle.map { "[\($0.role)]: \($0.content)" }.joined(separator: "\n")
        
        if let provider = provider {
            let summaryRequest = CompletionRequest(
                taskID: sessionID,
                systemPrompt: "Önceki konuşmalarının özetini çıkart. Teknik detayları, ulaşılan sonuçları ve kritik dosya yollarını koru.",
                messages: [Message(role: "user", content: "Şu konuşma geçmişini teknik bir özet haline getir:\n\n\(middleText)")],
                maxTokens: 1000,
                sensitivityLevel: .public,
                complexity: 2
            )
            
            let response = try await provider.complete(summaryRequest)
            let summaryMessage = Message(role: "system", content: "### GEÇMİŞ ÖZETİ (HISTORICAL SUMMARY):\n\(response.content)")
            
            self.messages = immutableHead + [summaryMessage] + tail
            os_log(.info, "[MEMORY]: Context auto-compacted into summary. New count: %d", self.messages.count)
        }
    }
    
    /// v9.9.6: High-performance trimming for TTFT reduction on local MLX models.
    public func trimMessages(limit: Int = 10) {
        guard messages.count > limit else { return }
        let head = Array(messages.prefix(1))
        let tail = Array(messages.suffix(limit - 1))
        self.messages = head + tail
    }
    
    public func clear() {
        messages.removeAll()
    }
}
