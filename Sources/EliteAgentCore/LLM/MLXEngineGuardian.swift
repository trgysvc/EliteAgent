import Foundation
import MLX
import Metal

#if canImport(Numerics)
import Numerics

// Linker shim: ensure at least one Numerics symbol is referenced so object files are not stripped as empty.
@inline(__always)
private func __ensureNumericsLinked() {
    // Use a complex value from Numerics to create a reference without runtime cost.
    let _ = Complex<Double>(0, 0)
}
#endif

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
    private var currentTask: Task<Sendable, Error>? // v24.7: Serialization Queue
    
    private init() {}
    
    #if canImport(Numerics)
    @usableFromInline
    static let __numericsLinkerAnchor: Void = {
        __ensureNumericsLinked()
        return ()
    }()
    #endif
    
    /// Executes an inference task with safety guardrails.
    public func execute<T: Sendable>(
        operation: @escaping @Sendable () async throws -> T
    ) async throws -> T {
        
        // v24.7: Serialization Logic
        // We await the completion of any existing task before starting the next one.
        // This prevents the 'Engine Busy' errors and ensures thread-safety for MLX.
        let previousTask = currentTask
        
        let newTask = Task { [previousTask] in
            // Wait for the previous task to finish (ignore its result/error)
            _ = await previousTask?.result
            
            // 1. Smart Cache Sanitization (v9.8)
            let vramUsage = self.calculateVRAMUsage()
            let thermalState = ProcessInfo.processInfo.thermalState
            
            if vramUsage > 0.90 || thermalState == .serious || thermalState == .critical {
                AgentLogger.logAudit(level: .warn, agent: "GUARDIAN", message: "[SMART CACHE] VRAM at \((vramUsage * 100).rounded())%. Purging cache.")
                MLX.Memory.clearCache()
            }
            
            // 2. Hardware Thermal Check
            if thermalState == .critical {
                throw EngineError.thermalCritical
            }
            
            // 3. Timeout Wrapper
            return try await withThrowingTaskGroup(of: T.self) { group in
                group.addTask {
                    try await operation()
                }
                
                group.addTask {
                    try await Task.sleep(nanoseconds: UInt64(self.timeoutLimit * 1_000_000_000))
                    throw EngineError.timeout
                }
                
                let result = try await group.next()!
                group.cancelAll()
                return result
            }
        }
        
        self.currentTask = Task { try await newTask.value }

        do {
            let value = try await newTask.value
            self.currentTask = nil
            return value
        } catch {
            self.currentTask = nil
            throw error
        }
    }
    
    /// Helper to perform emergency memory purge.
    public func emergencyPurge() {
        // v24.7: Do NOT purge if MLX is actively evaluating.
        if currentTask != nil {
            AgentLogger.logAudit(level: .warn, agent: "GUARDIAN", message: "Skipping Emergency Purge: Engine is actively evaluating.")
            return
        }
        
        AgentLogger.logAudit(level: .warn, agent: "GUARDIAN", message: "Emergency VRAM Purge Triggered.")
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

