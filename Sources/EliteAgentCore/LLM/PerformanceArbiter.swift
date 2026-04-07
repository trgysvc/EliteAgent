import Foundation
import OSLog

/// v10.5: EliteAgent Performance Arbiter
/// Implements PRD v6.8 (Dynamic Downscaling) and v6.9 (Hardware-Aware Concurrency).
public actor PerformanceArbiter {
    public static let shared = PerformanceArbiter()
    private let logger = Logger(subsystem: "com.elite.agent", category: "Performance")
    
    public enum PerformanceMode: String, Sendable {
        case nominal    // Full power
        case efficiency // Moderate downscaling (e.g. 32B -> 8B)
        case emergency  // Minimal power, halt new tasks
    }
    
    private init() {}
    
    /// Resolves the recommended model based on current system pressure and original request.
    /// Implements PRD v6.8 Dynamic Downscaling logic.
    public func resolveModelScale(originalID: ProviderID) async -> ProviderID {
        let pressure = ProcessInfo.processInfo.thermalState
        let ramGB = ProcessInfo.processInfo.physicalMemory / (1024 * 1024 * 1024)
        
        // v10.5: Rule-base based on PRD v6.9 Table
        switch pressure {
        case .serious, .critical:
            if originalID.rawValue.contains("32b") {
                logger.warning("Thermal pressure detected. Downscaling 32B -> 8B")
                return .mlx_r1_8b // Safe fallback
            }
        case .fair:
            if ramGB < 32 && originalID.rawValue.contains("32b") {
                 logger.warning("Low RAM & Fair thermal state. Downscaling for stability.")
                 return .mlx_r1_8b
            }
        default:
            break
        }
        
        return originalID
    }
    
    /// Calculates max concurrent workers based on PRD v13.5 Hardware-Aware Concurrency.
    public func determineMaxWorkers() -> Int {
        let thermal = ProcessInfo.processInfo.thermalState
        let ramGB = ProcessInfo.processInfo.physicalMemory / (1024 * 1024 * 1024)
        
        // PRD Rule: 1 worker per 8GB RAM (Base)
        let baseLevel = Int(ramGB / 8)
        
        switch thermal {
        case .nominal: return max(1, baseLevel)
        case .fair:    return max(1, baseLevel - 1)
        case .serious: return 1
        case .critical: return 0 // Halt execution
        @unknown default: return 1
        }
    }
    
    /// Returns the active performance mode for UI reporting.
    public func currentMode() -> PerformanceMode {
        let thermal = ProcessInfo.processInfo.thermalState
        switch thermal {
        case .nominal: return .nominal
        case .fair, .serious: return .efficiency
        case .critical: return .emergency
        @unknown default: return .nominal
        }
    }
}

// v10.5: Extension for ProviderID to match PRD aliases
extension ProviderID {
    static let mlx_r1_8b = ProviderID(rawValue: "mlx-r1-8b") ?? .mlx
    static let mlx_r1_32b = ProviderID(rawValue: "mlx-r1-32b") ?? .mlx
}
