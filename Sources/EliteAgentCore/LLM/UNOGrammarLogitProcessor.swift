import Foundation
import MLX
import MLXLLM
import MLXLMCommon

/// v13.2: UNO Grammar Masking Logit Processor
/// Enforces a strict output contract for "Action" blocks while allowing free-form "Thinking".
public struct UNOGrammarLogitProcessor: LogitProcessor, @unchecked Sendable {
    public enum Mode: Sendable {
        case thought      // Free text inside <think>
        case transition   // Text between </think> and <final>
        case action       // Strict UBID + Params inside <final>
        case summary      // Free text after </final>
    }
    
    private var mode: Mode = .thought
    private var buffer: String = ""
    private let tokenizer: Any
    private let allowedTokenIDs: Set<Int>
    private let controlTokenIDs: Set<Int>
    
    public init(tokenizer: Any, allowedTokenIDs: [Int], controlTokenIDs: [Int] = [151643, 151645, 10, 13]) {
        self.tokenizer = tokenizer
        self.allowedTokenIDs = Set(allowedTokenIDs)
        // Default control tokens for Qwen 2.5: EOS (151643), im_end (151645), \n (10), \r (13)
        self.controlTokenIDs = Set(controlTokenIDs)
    }
    
    public mutating func prompt(_ prompt: MLXArray) {
        mode = .thought
        buffer = ""
    }
    
    public func process(logits: MLXArray) -> MLXArray {
        // v13.8: Strict Phase-Locked Masking (User Requirement 2.3)
        guard mode == .action else { return logits }
        
        // v13.8: Building the Mask (User Requirement 2.1 & 2.2)
        // We allow ONLY tool UBIDs and vital control tokens.
        let fullAllowed = allowedTokenIDs.union(controlTokenIDs)
        
        // Note: Constructing a full mask array in every step might be expensive.
        // We use a optimized MLX mapping if possible.
        var mask = MLXArray.full(logits.shape, values: MLXArray(-Float.infinity))
        
        // v13.8: Allow safe tokens
        for id in fullAllowed {
            if id < logits.shape[0] {
                mask[id] = MLXArray(0.0)
            }
        }
        
        return logits + mask
    }
    
    public mutating func didSample(token: MLXArray) {
        let tokenID = Int(token.item(Int32.self))
        
        let text: String?
        if let bpe = tokenizer as? BPETokenizer {
            text = bpe.decode(tokens: [tokenID])
        } else {
            text = nil 
        }
        
        guard let text = text else { return }
        buffer += text
        
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
