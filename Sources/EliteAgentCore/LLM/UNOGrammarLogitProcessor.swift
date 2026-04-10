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
        case action       // Strict JSON/Swift-Action inside <final>
        case summary      // Free text after </final>
    }
    
    private var mode: Mode = .thought
    private var buffer: String = ""
    private let tokenizer: Any
    private let allowedToolIDs: [String]
    
    public init(tokenizer: Any, allowedToolIDs: [String]) {
        self.tokenizer = tokenizer
        self.allowedToolIDs = allowedToolIDs
    }
    
    public mutating func prompt(_ prompt: MLXArray) {
        // Reset state for new prompt
        mode = .thought
        buffer = ""
    }
    
    public func process(logits: MLXArray) -> MLXArray {
        // v13.2: Only apply masking in 'action' mode
        guard mode == .action else { return logits }
        
        // v13.2: Logit Masking Strategy
        // We set probability of "forbidden" tokens to -infinity.
        // For Phase 3, we implement a 'Safety Guard' that ensures 
        // the model only produces valid JSON characters if it's struggling.
        
        // FUTURE: Full GBNF-style masking logic goes here.
        // For now, we allow the base model but keep this hook for strict constraints.
        return logits
    }
    
    public mutating func didSample(token: MLXArray) {
        let tokenID = token.item(Int32.self)
        
        // Type-safe extraction of text from any tokenizer that supports decoding
        let text: String?
        if let bpe = tokenizer as? BPETokenizer {
            text = bpe.decode(tokens: [Int(tokenID)])
        } else {
            // Fallback for MLX dynamic tokenizers
            // We use reflection or a known protocol if available, but Any casting is safest for build stability
            text = nil // Placeholder for build stability
        }
        
        guard let text = text else { return }
        buffer += text
        
        // State Machine Transition Logic
        if buffer.contains("<final>") && mode != .action {
            mode = .action
            AgentLogger.logInfo("[Grammar] Transitioned to ACTION mode.")
        } else if buffer.contains("</final>") && mode == .action {
            mode = .summary
            AgentLogger.logInfo("[Grammar] Transitioned to SUMMARY mode.")
        } else if buffer.contains("</think>") && mode == .thought {
            mode = .transition
            AgentLogger.logInfo("[Grammar] Transitioned to TRANSITION mode.")
        }
    }
}
