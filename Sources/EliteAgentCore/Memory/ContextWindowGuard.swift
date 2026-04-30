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
    ///   - expectedResponseTokens: Predicted length of the next model response
    ///   - maxTokens: Maximum context window of the active model
    /// - Returns: A `GuardResult` indicating the appropriate action.
    public static func evaluate(
        messages: [Message],
        systemPromptTokens: Int = 1_500,
        expectedResponseTokens: Int = 1_000,
        maxTokens: Int = 8_192
    ) -> GuardResult {
        let messageTokens = estimateTokens(messages: messages)
        
        // v7.0: Preemptive Overflow Check (Native Sovereign Stability)
        // Formula: (Current + System + Buffer) * 1.2 Margin > Budget
        // This ensures we trigger compaction BEFORE the model hits the hard limit.
        let projectedTotal = Int(Double(messageTokens + systemPromptTokens + expectedResponseTokens) * 1.2)
        let currentTotal = messageTokens + systemPromptTokens
        
        let usageRatio = Double(projectedTotal) / Double(max(1, maxTokens))
        
        if maxTokens < hardMinTokens {
            return .block(
                message: "[CONTEXT_GUARD] Model context window too small (\(maxTokens) tokens). Minimum required: \(hardMinTokens).",
                usedTokens: currentTotal,
                maxTokens: maxTokens
            )
        }
        
        if usageRatio >= blockRatio {
            return .block(
                message: "[CONTEXT_GUARD] PREEMPTIVE BLOCK: Context projected to reach \(Int(usageRatio * 100))% with next response. Immediate compaction required.",
                usedTokens: currentTotal,
                maxTokens: maxTokens
            )
        }
        
        if usageRatio >= compactRatio {
            return .compact(
                message: "[CONTEXT_GUARD] PREEMPTIVE COMPACT: Projected usage \(Int(usageRatio * 100))% exceeds safety threshold (\(Int(compactRatio * 100))%). Triggering consolidation.",
                usedTokens: currentTotal,
                maxTokens: maxTokens
            )
        }
        
        if usageRatio >= warnRatio {
            return .warn(
                message: "[CONTEXT_GUARD] PREEMPTIVE WARN: Context window nearing limits (\(Int(usageRatio * 100))% projected).",
                usedTokens: currentTotal,
                maxTokens: maxTokens
            )
        }
        
        return .ok(usedTokens: currentTotal, maxTokens: maxTokens, usageRatio: usageRatio)
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
