import Foundation
import OSLog

/// Enforces strict output constraints (v10.0 'Brief Mode').
/// Protects token budget by ensuring compression ratios stay under 60%.
public struct OutputSchemaGuard {
    private static let logger = Logger(subsystem: "com.elite.agent", category: "SchemaGuard")
    
    /// Sanitizes LLM output based on configuration and token ratio.
    /// - Parameters:
    ///   - content: Raw response from LLM.
    ///   - inputTokens: Token count of the input prompt.
    ///   - config: Guard configuration.
    public static func sanitize(_ content: String, inputTokens: Int, config: TokenGuardConfig) -> String {
        // v10.0: Mandatory UI Sealing (Remove JSON Tool Calls and <think> Blocks)
        let uiCleaned = ThinkParser.cleanForUI(text: content)
        
        guard config.isBriefMode else { return uiCleaned }
        
        let outputTokens = estimateTokens(for: uiCleaned)
        let ratio = Double(outputTokens) / Double(max(1, inputTokens))
        
        // v10.0: Strict Compression Ratio (60% Threshold)
        if ratio > 0.60 {
            logger.warning("Output tokens exceed 60% of input. Truncating to maintain brief mode.")
            let targetTokens = Int(Double(inputTokens) * 0.60)
            return truncateSemantically(uiCleaned, targetTokens: targetTokens)
        }
        
        return uiCleaned
    }
    
    /// Truncates content while maintaining semantic integrity (complete sentences).
    private static func truncateSemantically(_ content: String, targetTokens: Int) -> String {
        // Simple heuristic: 1 token ~= 4 characters
        let targetChars = targetTokens * 4
        guard content.count > targetChars else { return content }
        
        let truncated = String(content.prefix(targetChars))
        return lastCompleteSentence(in: truncated) + " (Kısaltıldı - Brief Mode)"
    }
    
    /// Finds the last complete sentence in the given text.
    private static func lastCompleteSentence(in text: String) -> String {
        let sentenceEnders: CharacterSet = .init(charactersIn: ".!?")
        if let lastRange = text.rangeOfCharacter(from: sentenceEnders, options: .backwards) {
            return String(text[..<lastRange.upperBound])
        }
        return text // Fallback
    }
    
    private static func estimateTokens(for text: String) -> Int {
        // Real-world implementation would use a BPE tokenizer (like TicToken).
        // For v10.0, we use a calibrated character-based heuristic (4 chars/token).
        return (text.count / 4) + 1
    }
}
