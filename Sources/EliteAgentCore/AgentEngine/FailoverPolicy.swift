import Foundation

/// v7.0 Stability: Centralized Failover Logic (Native Sovereign)
/// Consolidates SelfHealingEngine, AutoRecoveryEngine, and LocalModelFailureDiagnostic 
/// into a single decision-making core.
public enum FailoverReason: Sendable {
    case timeout(seconds: Int)
    case contextOverflow(used: Int, max: Int)
    case memoryPressure(level: UNOMemoryPressureLevel)
    case modelHallucination(details: String)
    case performanceDrop(tps: Double)
    case toolExecutionError(error: String, tool: String)
}

public enum FailoverAction: Sendable {
    case compactMemory
    case reduceContext
    case restartLocalEngine
    case switchToCloud(reason: String)
    case notifyUser(message: String)
    case applyHealing(strategy: HealingStrategy)
    case none
}

public final class FailoverPolicy: Sendable {
    public static let shared = FailoverPolicy()
    
    private init() {}
    
    /// Resolves recovery action for high-level failover reasons.
    public func resolveFailoverAction(for reason: FailoverReason) -> FailoverAction {
        switch reason {
        case .timeout(let seconds):
            if seconds >= 60 {
                return .switchToCloud(reason: "Inference timed out after \(seconds)s.")
            }
            return .restartLocalEngine
            
        case .contextOverflow(let used, let max):
            let ratio = Double(used) / Double(max)
            if ratio >= 0.95 {
                return .switchToCloud(reason: "Context critically full (\(Int(ratio*100))%).")
            }
            return .compactMemory
            
        case .memoryPressure(let level):
            if level == .critical {
                return .switchToCloud(reason: "System memory pressure is CRITICAL.")
            } else if level == .warning {
                return .compactMemory // Proactive reduction
            }
            return .none
            
        case .modelHallucination(let details):
            return .notifyUser(message: "Model Hallucination Detected: \(details). Restarting engine...")
            
        case .performanceDrop(let tps):
            if tps < 1.0 {
                return .switchToCloud(reason: "Performance dropped to \(Int(tps)) t/s.")
            }
            return .reduceContext
            
        case .toolExecutionError(_, _):
            // Check if SelfHealingEngine can provide a strategy
            return .none
        }
    }
    
    /// Resolves recovery action specifically for LocalModelFailureReason (v27.0).
    public func resolveFailoverAction(for failure: LocalModelFailureReason) -> FailoverAction {
        switch failure {
        case .contextWindowOverflow:
            return .compactMemory
            
        case .outOfMemory:
            return .notifyUser(message: failure.userFacingExplanation)
            
        case .inferenceTimeout(let elapsed, _):
            if elapsed > 60_000 {
                return .switchToCloud(reason: "Inference Timeout (\(elapsed/1000)s)")
            }
            return .restartLocalEngine
            
        case .degenerateGeneration:
            return .restartLocalEngine
            
        case .toolCallFormatFailure:
            return .reduceContext // Reducing context might help model follow instructions better
            
        case .modelFileCorrupted:
            return .notifyUser(message: failure.userFacingExplanation)
            
        case .taskComplexityExceeded:
            return .switchToCloud(reason: "Task complexity exceeds local model capacity.")
            
        default:
            return .none
        }
    }
}
