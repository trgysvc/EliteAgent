import Foundation

@MainActor
public final class AutoRecoveryEngine: ObservableObject {
    public static let shared = AutoRecoveryEngine()
    
    private var recoveryAttempts = 0
    private let maxRecoveryAttempts = 3
    
    private init() {}
    
    public func attemptFix(_ metrics: InferenceMetrics) async {
        AgentLogger.logAudit(level: .warn, agent: "RECOVERY", message: "🔧 Soft Recovery Triggered: \(metrics.diagnostic)")
        
        // Step 1: Soft retry (clear KV cache / reduce context for NEXT request)
        await InferenceActor.shared.clearCache()
        await InferenceActor.shared.setNextRequestConfig(reducedContext: true)
        
        AgentLogger.logAudit(level: .info, agent: "RECOVERY", message: "Soft Fix applied: KV Cache cleared and next context reduced.")
    }
    
    public func forceRecovery(_ metrics: InferenceMetrics) async {
        AgentLogger.logAudit(level: .error, agent: "RECOVERY", message: "🚨 Hard Recovery Triggered (Attempt \(recoveryAttempts + 1)/\(maxRecoveryAttempts))")
        
        // Step 1: Immediate cache purge
        await InferenceActor.shared.clearCache()
        
        // Step 2: Reload model if repeat failure
        if recoveryAttempts == 1 {
            AgentLogger.logAudit(level: .warn, agent: "RECOVERY", message: "Reloading current model to stabilize VRAM...")
            await ModelSetupManager.shared.reloadCurrentModel()
        }
        
        // Step 3: Fallback to cloud if persistent
        if recoveryAttempts >= 2 {
            AgentLogger.logAudit(level: .error, agent: "RECOVERY", message: "Local model unstable. Switching to Cloud fallback.")
            await switchToCloudFallback()
        }
        
        recoveryAttempts += 1
        
        // Reset recovery counter after successful stabilization period (modeled as 5 mins)
        Task {
            try? await Task.sleep(nanoseconds: 300 * 1_000_000_000)
            self.recoveryAttempts = 0
        }
    }
    
    private func switchToCloudFallback() async {
        // v9.9: Switch via centralized ModelStateManager
        await ModelStateManager.shared.switchToCloud(reason: "Local model unstable")
    }
}
