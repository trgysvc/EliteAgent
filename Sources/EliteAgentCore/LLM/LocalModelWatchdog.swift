import Foundation
import SwiftUI
import Metal

@MainActor
public final class LocalModelWatchdog: ObservableObject {
    public static let shared = LocalModelWatchdog()
    
    @Published public var status: ModelHealthStatus = .offline
    @Published public var metrics: InferenceMetrics = .zero
    @Published public var history: [MetricSample] = []
    
    // v10.6: Live Activity
    @Published public var isBusy: Bool = false
    @Published public var loadedModelID: String? = nil
    
    private var healthTimer: Timer?
    private var lastMetricsFetch: Date = .distantPast
    private var lastRecoveryAttempt: Date = .distantPast
    private var cachedMetrics: InferenceMetrics = .zero
    private var isSimulatingStress: Bool = false
    
    private init() {
        startMonitoring()
    }
    
    public func startMonitoring() {
        healthTimer?.invalidate()
        healthTimer = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { [weak self] _ in
            Task { @MainActor in
                await self?.runHealthCheck()
            }
        }
    }
    
    public func runHealthCheck() async {
        // v10.7: Hybrid Availability Check (VRAM + File)
        let isActuallyLoaded = await InferenceActor.shared.isModelLoaded
        let isFilesReady = ModelSetupManager.shared.isModelReady
        
        // v10.7: Prioritize Live VRAM Presence
        if !isActuallyLoaded && !isFilesReady {
            if self.status != .offline {
                self.status = .offline
                self.isBusy = false
                self.loadedModelID = nil
                AgentLogger.logInfo("WATCHDOG: System is TRULY OFFLINE. No VRAM model and no valid files.")
            }
            return
        }
        
        // If we reach here, we are either Loaded in VRAM OR Files are Ready (or both).
        // If we were offline, we MUST move back to healthy.
        if self.status == .offline {
            self.status = .healthy
            AgentLogger.logAudit(level: .info, agent: "WATCHDOG", message: "System activity detected. Moving to ONLINE state.")
        }
        
        // v10.6: Sync Live Activity
        self.isBusy = await InferenceActor.shared.isBusy
        self.loadedModelID = await InferenceActor.shared.loadedModelID

        let currentMetrics = await collectMetrics()
        self.metrics = currentMetrics
        
        // Update History
        let sample = MetricSample(
            tokensPerSec: Float(currentMetrics.tokensPerSec),
            latencyMs: Float(currentMetrics.latencyMs),
            vramUsage: Float(currentMetrics.vramUsage),
            thermalState: currentMetrics.thermalState,
            status: self.status
        )
        self.history.append(sample)
        if self.history.count > 30 { self.history.removeFirst() }
        
        // v10.4: Cooldown and Busy-Safety
        let now = Date()
        let isBusy = await InferenceActor.shared.isBusy
        let isOnCooldown = now.timeIntervalSince(lastRecoveryAttempt) < 30.0
        
        // Threshold Logic
        if currentMetrics.vramUsage > 0.95 || currentMetrics.thermalState == 3 {
            self.status = .critical
            if !isOnCooldown && !isBusy {
                AgentLogger.logAudit(level: .error, agent: "WATCHDOG", message: "CRITICAL: Model performance severely degraded. Triggering immediate recovery.")
                await AutoRecoveryEngine.shared.forceRecovery(currentMetrics)
                self.lastRecoveryAttempt = now
            }
        } else if currentMetrics.vramUsage > 0.85 || currentMetrics.thermalState == 2 || (currentMetrics.tokensPerSec < 2.0 && currentMetrics.tokensPerSec > 0) {
            // v10.4: Lowered TPS threshold from 5 to 2.0 to be less aggressive.
            self.status = .degraded
            if !isOnCooldown && !isBusy {
                AgentLogger.logAudit(level: .warn, agent: "WATCHDOG", message: "DEGRADED: High resource usage / low TPS (\(currentMetrics.tokensPerSec) tok/s). Triggering soft optimization.")
                await AutoRecoveryEngine.shared.attemptFix(currentMetrics)
                self.lastRecoveryAttempt = now
            } else if isBusy {
                AgentLogger.logAudit(level: .info, agent: "WATCHDOG", message: "System is busy but TPS is low (\(currentMetrics.tokensPerSec) tok/s). Supportively waiting...")
            }
        } else {
            if self.status != .healthy {
                self.status = .healthy
                AgentLogger.logAudit(level: .info, agent: "WATCHDOG", message: "STABLE: System health restored.")
            }
        }
        
        // v9.7 Thermal Throttling Signal
        await MainActor.run {
            let isSerious = currentMetrics.thermalState >= 2
            if isSerious != AISessionState.shared.isThermalThrottled {
                AISessionState.shared.isThermalThrottled = isSerious
                if isSerious {
                    AgentLogger.logAudit(level: .warn, agent: "WATCHDOG", message: "[THERMAL] Serious heat detected. Throttling active.")
                }
            }
        }
    }
    
    private func collectMetrics() async -> InferenceMetrics {
        // Throttling: Cache metrics for 5 seconds
        guard Date().timeIntervalSince(lastMetricsFetch) > 5 else {
            return cachedMetrics
        }
        
        let tps = await InferenceActor.shared.getAverageTPS()
        let latency = await InferenceActor.shared.getLastLatency()
        let vram = calculateVRAMUsage()
        let thermal = ProcessInfo.processInfo.thermalState.rawValue
        
        let newMetrics = InferenceMetrics(
            tokensPerSec: tps,
            latencyMs: latency,
            vramUsage: vram,
            thermalState: thermal,
            errorRate: 0.0 // Placeholder for now
        )
        
        self.cachedMetrics = newMetrics
        self.lastMetricsFetch = Date()
        return newMetrics
    }
    
    // MARK: - v9.6 Extensions
    
    public func simulateStress() async {
        self.isSimulatingStress = true
        AgentLogger.logAudit(level: .warn, agent: "WATCHDOG", message: "🔥 Manual Stress Simulation Started.")
        
        // Force critical metrics override
        let stressMetrics = InferenceMetrics(
            tokensPerSec: 2.0,
            latencyMs: 5000,
            vramUsage: 0.98,
            thermalState: 3, // Critical
            errorRate: 0.5
        )
        
        self.metrics = stressMetrics
        self.status = .critical
        await AutoRecoveryEngine.shared.forceRecovery(stressMetrics)
        
        // Hold for 10 seconds then reset simulation
        Task {
            try? await Task.sleep(nanoseconds: 10 * 1_000_000_000)
            self.isSimulatingStress = false
            AgentLogger.logAudit(level: .info, agent: "WATCHDOG", message: "Stress simulation over. Resuming normal monitoring.")
            await runHealthCheck()
        }
    }
    
    public func exportMetrics() -> URL? {
        // v13.8: Unified Native Binary Serialization (No JSON Artıkları)
        let encoder = PropertyListEncoder()
        encoder.outputFormat = .binary
        
        guard let data = try? encoder.encode(history) else { return nil }
        let tempDir = FileManager.default.temporaryDirectory
        let fileURL = tempDir.appendingPathComponent("EliteAgent_Health_Metrics.plist")
        
        try? data.write(to: fileURL)
        return fileURL
    }
    
    private func calculateVRAMUsage() -> Double {
        if isSimulatingStress { return 0.98 }
        guard let device = MTLCreateSystemDefaultDevice() else { return 0.0 }
        
        // v9.6: Use recommendedMaxWorkingSetSize vs currentAllocatedSize
        let current = Double(device.currentAllocatedSize)
        let maxAvailable = Double(device.recommendedMaxWorkingSetSize)
        
        guard maxAvailable > 0 else { return 0.0 }
        return min(current / maxAvailable, 1.0)
    }
}
