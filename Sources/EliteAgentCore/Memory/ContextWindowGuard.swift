import Foundation
import OSLog

/// v27.0: Context Window Guard (OpenClaw-Inspired)
/// Monitors context window usage and triggers warnings or compaction before overflow.
/// Prevents the agent from silently losing context.
public struct ContextWindowGuard: Sendable {
    
    // MARK: - Thresholds (calibrated for local MLX models)
    
    /// Warn when context exceeds this ratio of max capacity.
    public static let warnRatio: Double = 0.70
    
    /// Trigger compaction when context exceeds this ratio.
    public static let compactRatio: Double = 0.85
    
    /// Block further inference when context exceeds this ratio.
    public static let blockRatio: Double = 0.95
    
    /// Minimum tokens required for meaningful inference.
    public static let hardMinTokens: Int = 2_000
    
    // MARK: - Types
    
    public enum GuardResult: Sendable {
        /// Context is within safe limits.
        case ok(usedTokens: Int, maxTokens: Int, usageRatio: Double)
        
        /// Context is getting full; inject a warning into the conversation.
        case warn(message: String, usedTokens: Int, maxTokens: Int)
        
        /// Context needs compaction before the next inference turn.
        case compact(message: String, usedTokens: Int, maxTokens: Int)
        
        /// Context is critically full; cannot proceed without drastic action.
        case block(message: String, usedTokens: Int, maxTokens: Int)
    }
    
    // MARK: - Public API
    
    /// Evaluates the current context window state.
    /// - Parameters:
    ///   - messages: Current conversation history
    ///   - systemPromptTokens: Estimated tokens used by the system prompt
    ///   - maxTokens: Maximum context window of the active model
    /// - Returns: A `GuardResult` indicating the appropriate action.
    public static func evaluate(
        messages: [Message],
        systemPromptTokens: Int = 1_500,
        maxTokens: Int = 8_192
    ) -> GuardResult {
        let messageTokens = estimateTokens(messages: messages)
        let totalUsed = messageTokens + systemPromptTokens
        let usageRatio = Double(totalUsed) / Double(max(1, maxTokens))
        
        if maxTokens < hardMinTokens {
            return .block(
                message: "[CONTEXT_GUARD] Model context window too small (\(maxTokens) tokens). Minimum required: \(hardMinTokens). Cannot proceed with meaningful inference.",
                usedTokens: totalUsed,
                maxTokens: maxTokens
            )
        }
        
        if usageRatio >= blockRatio {
            return .block(
                message: "[CONTEXT_GUARD] CRITICAL: Context window is \(Int(usageRatio * 100))% full (\(totalUsed)/\(maxTokens) tokens). Cannot add more messages without losing critical information. Immediate compaction or session reset required.",
                usedTokens: totalUsed,
                maxTokens: maxTokens
            )
        }
        
        if usageRatio >= compactRatio {
            return .compact(
                message: "[CONTEXT_GUARD] Context window is \(Int(usageRatio * 100))% full (\(totalUsed)/\(maxTokens) tokens). Automatic compaction triggered to preserve task context.",
                usedTokens: totalUsed,
                maxTokens: maxTokens
            )
        }
        
        if usageRatio >= warnRatio {
            return .warn(
                message: "[CONTEXT_GUARD] Context window is \(Int(usageRatio * 100))% full (\(totalUsed)/\(maxTokens) tokens). Be concise in your responses to avoid context overflow.",
                usedTokens: totalUsed,
                maxTokens: maxTokens
            )
        }
        
        return .ok(usedTokens: totalUsed, maxTokens: maxTokens, usageRatio: usageRatio)
    }
    
    // MARK: - Token Estimation
    
    /// Estimates token count using the standard 4-characters-per-token heuristic.
    /// This is consistent with EliteAgent's existing BriefFormatter calibration.
    public static func estimateTokens(messages: [Message]) -> Int {
        let totalChars = messages.reduce(0) { $0 + $1.content.count }
        return totalChars / 4
    }
    
    /// Estimates tokens for a single string.
    public static func estimateTokens(text: String) -> Int {
        return text.count / 4
    }
}
