import Foundation
import OSLog

/// v27.0: Hardened Context Manager with OpenClaw-Inspired Compaction.
/// Implements evidence-preserving summarization and context window monitoring.
public actor DynamicContextManager {
    private var messages: [Message] = []
    private let maxTokens: Int
    private let threshold: Double = 0.8
    private weak var provider: CloudProvider?
    
    /// The index after which messages are considered 'recent' and protected from summarization.
    private var compactBoundary: Int = 10
    
    /// v27.0: Track compaction events for trajectory recording.
    private var compactionCount: Int = 0
    
    public init(maxTokens: Int, provider: CloudProvider?) {
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
    
    /// Returns the current compaction count.
    public func getCompactionCount() -> Int {
        return compactionCount
    }
    
    // MARK: - v27.0: OpenClaw-Inspired Compaction Engine
    
    /// English-language compaction prompt with MUST PRESERVE rules.
    /// This ensures the agent never loses critical task context during summarization.
    private static let compactionSystemPrompt = """
    You are a context compaction engine. Your job is to summarize the conversation history 
    into a concise technical summary while preserving ALL critical information.
    
    MUST PRESERVE in your summary:
    - Active tasks and their current status (in-progress, blocked, pending, completed)
    - Batch operation progress (e.g., '5/17 items completed', 'files 1-67 done')
    - The LAST thing the user requested and what was being done about it
    - Decisions made and their rationale
    - TODOs, open questions, and constraints mentioned
    - Any commitments or follow-ups promised
    - File paths, directory structures, and command outputs that are still relevant
    - Error messages encountered and how they were resolved (or not)
    - Tool call results that inform the next steps
    
    MUST OMIT:
    - Redundant greetings, acknowledgements, and filler text
    - Duplicate information already captured in a newer message
    - System protocol messages (CALL, UBID, THINK blocks) — summarize their EFFECT only
    - Verbose tool outputs where only the conclusion matters
    
    OUTPUT FORMAT: A structured summary with clear sections. Use bullet points.
    Keep the summary under 800 tokens. Be precise and factual.
    """
    
    /// v27.0: Intelligent Context Compaction with evidence preservation.
    /// Uses any available LLM provider (local or cloud) for summarization.
    public func compress(sessionID: String, localProvider: (any LLMProvider)? = nil) async throws {
        let totalChars = messages.reduce(0) { $0 + ($1.content.count) }
        let estimatedTokens = totalChars / 4
        
        guard Double(estimatedTokens) > Double(maxTokens) * threshold else { return }
        
        // Strategy:
        // 1. Keep System Prompt (0) and Initial Goal (1) — immutable head
        // 2. Summarize everything between index 2 and (messages.count - compactBoundary)
        // 3. Keep the last 'compactBoundary' messages as is — recent context
        
        guard messages.count > (compactBoundary + 5) else { return }
        
        let immutableHead = Array(messages.prefix(2))
        let tail = Array(messages.suffix(compactBoundary))
        let middle = Array(messages[2..<(messages.count - compactBoundary)])
        
        let middleText = middle.map { "[\($0.role)]: \($0.content)" }.joined(separator: "\n")
        
        let tokensBefore = estimatedTokens
        
        // v27.0: Provider selection — prefer local, fallback to cloud
        let activeProvider: (any LLMProvider)? = localProvider ?? (provider as (any LLMProvider)?)
        
        if let activeProvider = activeProvider {
            let summaryRequest = CompletionRequest(
                taskID: sessionID,
                systemPrompt: Self.compactionSystemPrompt,
                messages: [Message(role: "user", content: "Summarize the following conversation history:\n\n\(middleText)")],
                maxTokens: 1000,
                sensitivityLevel: .public,
                complexity: 2
            )
            
            let response = try await activeProvider.complete(summaryRequest, useSafeMode: false)
            let summaryMessage = Message(role: "system", content: "### COMPACTED CONTEXT (Turn \(compactionCount + 1)):\n\(response.content)")
            
            self.messages = immutableHead + [summaryMessage] + tail
            self.compactionCount += 1
            
            let tokensAfter = self.messages.reduce(0) { $0 + ($1.content.count) } / 4
            os_log(.info, "[CONTEXT] Compacted: %d → %d tokens (saved %d). Compaction #%d",
                   tokensBefore, tokensAfter, tokensBefore - tokensAfter, compactionCount)
            
            AgentLogger.logAudit(
                level: .info,
                agent: "ContextManager",
                message: "📦 [COMPACTION #\(compactionCount)] \(tokensBefore) → \(tokensAfter) tokens. \(middle.count) messages summarized."
            )
        }
    }
    
    /// v9.9.6: High-performance trimming for TTFT reduction on local MLX models.
    /// v27.0: Now logs when trimming occurs so the agent is aware of context loss.
    public func trimMessages(limit: Int = 10) {
        guard messages.count > limit else { return }
        let head = Array(messages.prefix(1))
        let tail = Array(messages.suffix(limit - 1))
        let trimmedCount = messages.count - limit
        self.messages = head + tail
        
        os_log(.info, "[CONTEXT] Trimmed %d messages (kept head + last %d). Context loss risk.", trimmedCount, limit - 1)
        AgentLogger.logAudit(
            level: .warn,
            agent: "ContextManager",
            message: "✂️ [TRIM] \(trimmedCount) messages removed. Consider using compress() for evidence-preserving compaction."
        )
    }
    
    public func clear() {
        messages.removeAll()
        compactionCount = 0
    }
}
