import Foundation
import MLX
import Metal

public enum EngineError: LocalizedError {
    case timeout
    case outOfMemory
    case thermalCritical
    case unknown(String)
    
    public var errorDescription: String? {
        switch self {
        case .timeout: return "Çıkarım işlemi zaman aşımına uğradı (60s). Grafik işlemci (GPU) yanıt vermiyor."
        case .outOfMemory: return "Video belleği (VRAM) tükendi. Motor yeniden başlatılıyor..."
        case .thermalCritical: return "Cihaz aşırı ısındı. Güvenlik nedeniyle işlem durduruldu."
        case .unknown(let msg): return "Beklenmedik motor hatası: \(msg)"
        }
    }
}

public actor MLXEngineGuardian {
    public static let shared = MLXEngineGuardian()
    
    private let timeoutLimit: TimeInterval = 180.0 // v9.8: 3 minutes for long research reports
    private var isEvaluating = false // v24.1: Concurrency Guard
    
    private init() {}
    
    /// Executes an inference task with safety guardrails.
    public func execute<T: Sendable>(
        operation: @escaping @Sendable () async throws -> T
    ) async throws -> T {
        
        // v24.1: Strict Re-entrancy Check
        if isEvaluating {
            AgentLogger.logAudit(level: .warn, agent: "GUARDIAN", message: "Concurrent evaluation detected. Aborting nested execution to prevent mutex crash.")
            throw EngineError.unknown("Motor meşgul.")
        }
        
        isEvaluating = true
        
        // 1. Smart Cache Sanitization (v9.8)
        // Only clears VRAM if usage exceeds 90% or thermal is serious.
        let vramUsage = calculateVRAMUsage()
        let thermalState = ProcessInfo.processInfo.thermalState
        
        if vramUsage > 0.90 || thermalState == .serious || thermalState == .critical {
            AgentLogger.logAudit(level: .warn, agent: "GUARDIAN", message: "[SMART CACHE] VRAM at \((vramUsage * 100).rounded())%. Purging cache to maintain stability.")
            MLX.eval()
            MLX.Memory.clearCache()
        }
        
        // 2. Hardware Thermal Check
        if thermalState == .critical {
            isEvaluating = false
            throw EngineError.thermalCritical
        }
        
        // 3. Timeout Wrapper
        do {
            let result = try await withThrowingTaskGroup(of: T.self) { group in
                group.addTask {
                    try await operation()
                }
                
                group.addTask {
                    try await Task.sleep(nanoseconds: UInt64(self.timeoutLimit * 1_000_000_000))
                    throw EngineError.timeout
                }
                
                // Return first result or first error
                let result = try await group.next()!
                group.cancelAll() // Cancel the other task (either timeout or the operation)
                return result
            }
            isEvaluating = false
            return result
        } catch {
            isEvaluating = false
            throw error
        }
    }
    
    /// Helper to perform emergency memory purge.
    public func emergencyPurge() {
        // v24.1: Do NOT purge if MLX is actively evaluating. This corrupts the C++ Mutex.
        if isEvaluating {
            AgentLogger.logAudit(level: .warn, agent: "GUARDIAN", message: "Skipping Emergency Purge: Engine is actively evaluating. Purging now would crash the ThreadPool.")
            return
        }
        
        AgentLogger.logAudit(level: .warn, agent: "GUARDIAN", message: "Emergency VRAM Purge Triggered.")
        MLX.eval()
        MLX.Memory.clearCache()
    }
    
    private func calculateVRAMUsage() -> Double {
        guard let device = MTLCreateSystemDefaultDevice() else { return 0.0 }
        let current = Double(device.currentAllocatedSize)
        let maxAvailable = Double(device.recommendedMaxWorkingSetSize)
        guard maxAvailable > 0 else { return 0.0 }
        return min(current / maxAvailable, 1.0)
    }
}
