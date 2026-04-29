import Foundation

/// v27.0: Local Model Failure Diagnostic Engine
/// Categorizes 12 distinct failure reasons for local LLM inference,
/// provides user-facing explanations, and suggests remedies BEFORE cloud fallback.
/// Cloud fallback NEVER happens automatically — user approval is ALWAYS required.
public enum LocalModelFailureReason: Sendable {
    
    // MARK: - Capacity / Architecture Limits
    
    /// The conversation + system prompt exceeds the model's maximum context window.
    case contextWindowOverflow(usedTokens: Int, maxTokens: Int)
    
    /// The task requires reasoning beyond the model's capacity (detected via loops or hallucinations).
    case taskComplexityExceeded(evidence: String)
    
    /// 4-bit quantization introduced precision errors affecting output quality.
    case quantizationDegradation
    
    /// The model failed to produce valid tool call format (binary signature / UBID).
    case toolCallFormatFailure(parseError: String)
    
    // MARK: - System Resources
    
    /// Unified memory is insufficient for inference (other apps consuming RAM).
    case outOfMemory(availableGB: Double, requiredGB: Double)
    
    /// Apple Silicon is thermally throttled, causing inference timeouts.
    case thermalThrottling(state: String)
    
    /// Inference exceeded the maximum allowed time.
    case inferenceTimeout(elapsedMs: Int, limitMs: Int)
    
    // MARK: - Technical / Infrastructure
    
    /// MLX Metal shader failed to compile on this hardware configuration.
    case metalShaderError(detail: String)
    
    /// Model entered a degenerate state producing infinite token repetition.
    case degenerateGeneration(repetitionCount: Int)
    
    /// Model weight files are corrupted or incomplete.
    case modelFileCorrupted(path: String)
    
    // MARK: - Guidance Issues
    
    /// System prompt does not adequately guide the model for this task type.
    case promptEngineeringFailure(symptom: String)
    
    /// The model lacks sufficient training data for this domain/language.
    case domainMismatch(domain: String)
    
    // MARK: - User-Facing Explanation
    
    /// A detailed, non-technical explanation of why the local model failed.
    /// This MUST be shown to the user before any fallback decision.
    public var userFacingExplanation: String {
        switch self {
        case .contextWindowOverflow(let used, let max):
            return "The conversation history (\(used) tokens) exceeds the local model's maximum capacity (\(max) tokens). The model cannot process any more information in this session."
            
        case .taskComplexityExceeded(let evidence):
            return "This task requires reasoning capabilities beyond the local model's capacity. Evidence: \(evidence). A more powerful model may be needed."
            
        case .quantizationDegradation:
            return "The 4-bit quantized model is producing imprecise results for this task. Full-precision inference would improve accuracy but requires more memory."
            
        case .toolCallFormatFailure(let error):
            return "The local model failed to produce a valid tool call format. Parse error: \(error). This typically indicates the model hasn't been adequately fine-tuned for tool use."
            
        case .outOfMemory(let available, let required):
            return "Insufficient memory for inference. Available: \(String(format: "%.1f", available))GB, Required: \(String(format: "%.1f", required))GB. Close other applications to free memory."
            
        case .thermalThrottling(let state):
            return "The system is thermally throttled (\(state)). The processor has slowed down to prevent overheating, causing inference to time out. Allow the system to cool down."
            
        case .inferenceTimeout(let elapsed, let limit):
            return "Inference took too long (\(elapsed)ms, limit: \(limit)ms). This may be caused by a very long output request or system load."
            
        case .metalShaderError(let detail):
            return "GPU shader compilation failed: \(detail). This is a hardware compatibility issue with the MLX inference engine."
            
        case .degenerateGeneration(let count):
            return "The model entered a repetition loop (repeated the same token \(count) times). This indicates the model is stuck and cannot produce meaningful output."
            
        case .modelFileCorrupted(let path):
            return "Model file appears corrupted at: \(path). Re-download the model to fix this issue."
            
        case .promptEngineeringFailure(let symptom):
            return "The system prompt may not be optimal for this task type. Symptom: \(symptom). The task might work better with adjusted instructions."
            
        case .domainMismatch(let domain):
            return "The local model has limited knowledge in the '\(domain)' domain. A cloud model with broader training data may produce better results."
        }
    }
    
    // MARK: - Local Remedies
    
    /// Suggested actions to try BEFORE resorting to cloud fallback.
    /// These are ordered from least to most disruptive.
    public var localRemedies: [String] {
        switch self {
        case .contextWindowOverflow:
            return [
                "Trigger context compaction to summarize older messages",
                "Split the task into smaller chunks (Adaptive Chunking)",
                "Start a new session focused on the remaining work"
            ]
            
        case .taskComplexityExceeded:
            return [
                "Break the task into simpler, sequential sub-tasks",
                "Provide more explicit step-by-step instructions",
                "Use a larger local model if available"
            ]
            
        case .quantizationDegradation:
            return [
                "Switch to a higher precision model (fp16 if memory allows)",
                "Simplify the numerical/analytical requirements",
                "Verify critical calculations manually"
            ]
            
        case .toolCallFormatFailure:
            return [
                "Retry with a simplified prompt",
                "Use a different local model trained for tool use",
                "Manually specify the tool and parameters"
            ]
            
        case .outOfMemory:
            return [
                "Close unused applications to free memory",
                "Use a smaller model (e.g., 3B instead of 7B)",
                "Wait for background processes to complete"
            ]
            
        case .thermalThrottling:
            return [
                "Wait 2-3 minutes for the system to cool down",
                "Reduce ambient temperature or improve ventilation",
                "Use eco-inference mode for lower power consumption"
            ]
            
        case .inferenceTimeout:
            return [
                "Reduce the expected output length",
                "Simplify the request",
                "Check for background system load"
            ]
            
        case .metalShaderError:
            return [
                "Restart the application",
                "Update macOS to the latest version",
                "Try a different model architecture"
            ]
            
        case .degenerateGeneration:
            return [
                "Adjust temperature/sampling parameters",
                "Rephrase the prompt to avoid repetitive patterns",
                "Use a different model"
            ]
            
        case .modelFileCorrupted:
            return [
                "Re-download the model files",
                "Verify disk integrity",
                "Use a different model"
            ]
            
        case .promptEngineeringFailure:
            return [
                "Rephrase the request more explicitly",
                "Provide examples of the expected output format",
                "Break the task into clearer steps"
            ]
            
        case .domainMismatch:
            return [
                "Provide additional context about the domain",
                "Use simpler, more universal terminology",
                "Consider a domain-specific local model"
            ]
        }
    }
    
    // MARK: - Failure Category
    
    /// High-level category for the failure reason.
    public var category: String {
        switch self {
        case .contextWindowOverflow, .taskComplexityExceeded,
             .quantizationDegradation, .toolCallFormatFailure:
            return "Model Capacity"
        case .outOfMemory, .thermalThrottling, .inferenceTimeout:
            return "System Resources"
        case .metalShaderError, .degenerateGeneration, .modelFileCorrupted:
            return "Technical"
        case .promptEngineeringFailure, .domainMismatch:
            return "Guidance"
        }
    }
    
    // MARK: - Structured User Notification
    
    /// Generates the full structured notification to show to the user.
    /// This includes the reason, explanation, local remedies, and fallback option.
    public func buildUserNotification(modelName: String = "Local Model") -> String {
        let remedyList = localRemedies.enumerated()
            .map { "  \($0.offset + 1). \($0.element)" }
            .joined(separator: "\n")
        
        return """
        ⚠️ LOCAL MODEL CAPACITY REPORT
        
        Model: \(modelName)
        Category: \(category)
        
        Reason: \(userFacingExplanation)
        
        Suggested Actions (try these first):
        \(remedyList)
        
        If these actions are insufficient:
          A cloud model (OpenRouter) may be able to complete this task.
          
          [✓ Switch to Cloud Model]  [↻ Retry Locally]  [✕ Cancel]
        """
    }
}
