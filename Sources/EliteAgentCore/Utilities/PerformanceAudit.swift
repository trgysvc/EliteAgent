import Foundation
import Metal
import MLX

public struct M4PerformanceAudit {
    public static func checkCapacity() -> String {
        let device = MTLCreateSystemDefaultDevice()
        let name = device?.name ?? "Unknown"
        
        let supportsMetal3 = device?.supportsFamily(.apple8) ?? false 
        let supportsRayTracing = device?.supportsRaytracing ?? false
        let supportsM4Features = device?.supportsFamily(.apple9) ?? false // M4-specific tier
        
        let mem = ProcessInfo.processInfo.physicalMemory / (1024 * 1024 * 1024)
        let cacheLimit = MLX.Memory.cacheLimit / (1024 * 1024 * 1024)
        
        return """
        [M4 HARDWARE CAPACITY AUDIT]
        - GPU Identity: \(name)
        - Metal 3.x Standard: \(supportsMetal3 ? "PASS" : "FAIL")
        - HW Ray Tracing: \(supportsRayTracing ? "ACTIVE" : "INACTIVE")
        - M4 Features: \(supportsM4Features ? "ACTIVE" : "INACTIVE")
        - Unified Memory: \(mem) GB Total
        - MLX VRAM Allocation: \(cacheLimit) GB (Active UMA Cache)
        """
    }
}
