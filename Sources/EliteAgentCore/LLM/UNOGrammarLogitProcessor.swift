import Foundation
import MLX
import MLXLLM
import MLXLMCommon
import Tokenizers

/// v13.2: UNO Grammar Masking Logit Processor
/// Enforces a strict output contract for "Action" blocks while allowing free-form "Thinking".
public final class UNOGrammarLogitProcessor: LogitProcessor, @unchecked Sendable {
    public enum Mode: Sendable {
        case thought      // Free text inside <think>
        case transition   // Text between </think> and <final>
        case action       // Strict UBID + Params inside <final>
        case summary      // Free text after </final>
    }
    
    private var mode: Mode = .thought
    private var buffer: String = ""
    private let tokenizer: Tokenizers.Tokenizer
    private let allowedTokenIDs: Set<Int>
    private let controlTokenIDs: Set<Int>
    
    public init(tokenizer: Tokenizers.Tokenizer, allowedTokenIDs: [Int], controlTokenIDs: [Int] = [151643, 151645, 10, 13]) {
        self.tokenizer = tokenizer
        self.allowedTokenIDs = Set(allowedTokenIDs)
        // Default control tokens for Qwen 2.5: EOS (151643), im_end (151645), \n (10), \r (13)
        // Plus vital JSON/Grammar tokens: { } [ ] " : , (ASCII)
        let vitalTokens = Set(controlTokenIDs)
        
        // We need to fetch ID for these characters dynamically or use common ones
        // For Qwen 2.5, we'll try to identify them in InferenceActor before passing
        self.controlTokenIDs = vitalTokens
    }
    
    public func prompt(_ prompt: MLXArray) {
        mode = .thought
        buffer = ""
    }
    
    public func process(logits: MLXArray) -> MLXArray {
        // v13.8: Strict Phase-Locked Masking (User Requirement 2.3)
        // If we are in ACTION mode, we enforce the protocol.
        guard mode == .action else { return logits }
        
        // v14.1: Dynamic Binary Masking
        let mask = MLXArray.full(logits.shape, values: MLXArray(-Float.infinity))
        
        // v14.1: Allow logic - effectively blocking single quotes and other deviations
        let allAllowed = allowedTokenIDs.union(controlTokenIDs)
        for id in allAllowed {
            if id < logits.shape[0] {
                mask[id] = MLXArray(0.0)
            }
        }
        
        return logits + mask
    }
    
    public func didSample(tokenText: String) {
        buffer += tokenText
        updateState()
    }
    
    public func didSample(token: MLXArray) {
        let tokenID = Int(token.item(Int32.self))
        
        let text: String?
        text = tokenizer.decode(tokens: [tokenID])
        
        guard let text = text else { return }
        buffer += text
        updateState()
    }
    
    private func updateState() {
        // State Machine Transition Logic
        if buffer.contains("<final>") && mode != .action {
            mode = .action
            AgentLogger.logInfo("[Grammar] Transitioned to ACTION mode. Masking active.")
        } else if buffer.contains("</final>") && mode == .action {
            mode = .summary
            AgentLogger.logInfo("[Grammar] Transitioned to SUMMARY mode. Masking disabled.")
        } else if buffer.contains("</think>") && mode == .thought {
            mode = .transition
            AgentLogger.logInfo("[Grammar] Transitioned to TRANSITION mode.")
        }
    }
}
