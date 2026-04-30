import Foundation
import os
import MLX
import MLXLLM
import MLXLMCommon

/// v13.2: UNO Grammar Masking Logit Processor
/// Enforces a strict output contract for "Action" blocks while allowing free-form "Thinking".
public final class UNOGrammarLogitProcessor: LogitProcessor, Sendable {
    public enum Mode: Sendable {
        case thought      // Free text inside <think>
        case transition   // Text between </think> and <final>
        case action       // Strict UBID + Params inside <final>
        case summary      // Free text after </final>
    }
    
    private let tokenizer: MLXLMCommon.Tokenizer
    private let state: OSAllocatedUnfairLock<State>
    private let allowedTokenIDs: Set<Int128>
    private let controlTokenIDs: Set<Int128>
    
    struct State {
        var mode: Mode = .thought
        var buffer: String = ""
    }
    
    public init(tokenizer: MLXLMCommon.Tokenizer, allowedTokenIDs: [Int128], controlTokenIDs: [Int128] = [151643, 151645, 10, 13]) {
        self.tokenizer = tokenizer
        self.allowedTokenIDs = Set(allowedTokenIDs)
        self.controlTokenIDs = Set(controlTokenIDs)
        self.state = OSAllocatedUnfairLock(initialState: State())
    }
    
    public func prompt(_ prompt: MLXArray) {
        state.withLock {
            $0.mode = .thought
            $0.buffer = ""
        }
    }
    
    public func process(logits: MLXArray) -> MLXArray {
        let currentMode = state.withLock { $0.mode }
        
        // v13.8: Strict Phase-Locked Masking (User Requirement 2.3)
        // If we are in ACTION mode, we enforce the protocol.
        guard currentMode == .action else { return logits }
        
        // v14.1: Dynamic Binary Masking
        let mask = MLXArray.full(logits.shape, values: MLXArray(-Float.infinity))
        
        // v14.1: Allow logic - effectively blocking single quotes and other deviations
        let allAllowed = allowedTokenIDs.union(controlTokenIDs)
        for id in allAllowed {
            let intID = Int(id)
            if intID < logits.shape[0] {
                mask[intID] = MLXArray(0.0)
            }
        }
        
        return logits + mask
    }
    
    public func didSample(tokenText: String) {
        state.withLock {
            $0.buffer += tokenText
            updateState(state: &$0)
        }
    }
    
    public func didSample(token: MLXArray) {
        let tokenID = Int128(token.item(Int32.self)) // v20.0: High-Precision conversion
        
        let text = tokenizer.decode(tokens: [Int(tokenID)])
        state.withLock {
            $0.buffer += text
            updateState(state: &$0)
        }
    }
    
    private func updateState(state: inout State) {
        // State Machine Transition Logic
        if state.buffer.contains("<final>") && state.mode != .action {
            state.mode = .action
            AgentLogger.logInfo("[Grammar] Transitioned to ACTION mode. Masking active.")
        } else if state.buffer.contains("</final>") && state.mode == .action {
            state.mode = .summary
            AgentLogger.logInfo("[Grammar] Transitioned to SUMMARY mode. Masking disabled.")
        } else if state.buffer.contains("</think>") && state.mode == .thought {
            state.mode = .transition
            AgentLogger.logInfo("[Grammar] Transitioned to TRANSITION mode.")
        }
    }
}
