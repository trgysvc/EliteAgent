import Foundation
import SwiftUI
import Metal

@MainActor
public final class LocalModelWatchdog: ObservableObject {
    public static let shared = LocalModelWatchdog()
    
    @Published public var status: ModelHealthStatus = .offline
    @Published public var metrics: InferenceMetrics = .zero
    @Published public var history: [MetricSample] = []
    
    private var healthTimer: Timer?
    private var lastMetricsFetch: Date = .distantPast
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
        // v9.9.9: Data-Driven Availability Check
        let isReady = ModelSetupManager.shared.isModelReady
        
        if !isReady {
            if self.status != .offline {
                self.status = .offline
                AgentLogger.logInfo("WATCHDOG: Local model is not loaded. Status set to OFFLINE.")
            }
            return
        }

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
        
        // Threshold Logic
        if currentMetrics.vramUsage > 0.95 || currentMetrics.thermalState == 3 {
            self.status = .critical
            AgentLogger.logAudit(level: .error, agent: "WATCHDOG", message: "CRITICAL: Model performance severely degraded. Triggering immediate recovery.")
            await AutoRecoveryEngine.shared.forceRecovery(currentMetrics)
        } else if currentMetrics.vramUsage > 0.85 || currentMetrics.thermalState == 2 || currentMetrics.tokensPerSec < 5 && currentMetrics.tokensPerSec > 0 {
            self.status = .degraded
            AgentLogger.logAudit(level: .warn, agent: "WATCHDOG", message: "DEGRADED: High resource usage / low TPS. Triggering soft optimization.")
            await AutoRecoveryEngine.shared.attemptFix(currentMetrics)
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
        let encoder = JSONEncoder()
        encoder.outputFormatting = .prettyPrinted
        
        guard let data = try? encoder.encode(history) else { return nil }
        let tempDir = FileManager.default.temporaryDirectory
        let fileURL = tempDir.appendingPathComponent("EliteAgent_Health_Metrics.json")
        
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
