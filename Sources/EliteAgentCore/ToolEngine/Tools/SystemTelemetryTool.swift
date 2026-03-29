import Foundation
import AppKit

/// SystemTelemetryTool: EliteAgent'ın donanım farkındalığını (isı, bellek, CPU yükü) sağlayan çekirdek araç.
/// Bu araç sayesinde ajan, Apple Silicon mimarisinin o anki durumuna göre strateji belirleyebilir.
public struct SystemTelemetryTool: AgentTool {
    public let name = "get_system_telemetry"
    public let description = "Retrieve real-time hardware status including thermal state, memory pressure, and performance metrics."
    
    public init() {}
    
    public func execute(params: [String: AnyCodable], session: Session) async throws -> String {
        let processInfo = ProcessInfo.processInfo
        
        // 1. Thermal State
        let thermalState = processInfo.thermalState
        let thermalDescription: String
        switch thermalState {
        case .nominal: thermalDescription = "Nominal (Cool)"
        case .fair: thermalDescription = "Fair (Normal)"
        case .serious: thermalDescription = "Serious (Throttling likely)"
        case .critical: thermalDescription = "Critical (Immediate Throttling)"
        @unknown default: thermalDescription = "Unknown"
        }
        
        // 2. Memory Pressure (via host_statistics64 if needed, but ProcessInfo provides basic)
        // For simplicity in native Swift, we'll use a shell bridge for detailed memory if needed,
        // but thermal is the most critical for the "M-series mastery" prompt.
        
        // 3. System Load (Basic)
        let processorCount = processInfo.processorCount
        let activeProcessorCount = processInfo.activeProcessorCount
        let upTime = processInfo.systemUptime
        
        // 4. Memory Usage (Rough estimate)
        let memoryUsed = Double(getTotalMemoryUsed()) / (1024 * 1024 * 1024) // GB
        let totalRAM = Double(processInfo.physicalMemory) / (1024 * 1024 * 1024) // GB
        
        let report = """
        [System Telemetry Report]
        - Thermal State: \(thermalDescription)
        - Processor Cores: \(processorCount) (Active: \(activeProcessorCount))
        - RAM Usage: \(String(format: "%.2f", memoryUsed)) GB / \(String(format: "%.2f", totalRAM)) GB
        - System Uptime: \(Int(upTime / 3600)) hours
        - M-Series Check: \(isAppleSilicon() ? "Confirmed (Apple Silicon)" : "Intel/Other")
        - Recommendations: \(getRecommendations(thermalState: thermalState))
        """
        
        return report
    }
    
    private func getTotalMemoryUsed() -> UInt64 {
        var stats = mach_task_basic_info()
        var count = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info>.size) / 4
        
        let kerr: kern_return_t = withUnsafeMutablePointer(to: &stats) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(MACH_TASK_BASIC_INFO), $0, &count)
            }
        }
        
        if kerr != KERN_SUCCESS {
            // Graceful Degradation: If Mach kernel call fails, return a safe estimate or handle error
            print("[TELEMETRY] Mach task_info failed (err: \(kerr)). Falling back to AppKit/ProcessInfo.")
            return ProcessInfo.processInfo.physicalMemory / 4 // Fallback 25% estimate
        }
        
        return stats.resident_size
    }
    
    private func isAppleSilicon() -> Bool {
        #if arch(arm64)
        return true
        #else
        return false
        #endif
    }
    
    private func getRecommendations(thermalState: ProcessInfo.ThermalState) -> String {
        switch thermalState {
        case .nominal, .fair:
            return "Stable. You can utilize high-performance Metal and ANE pipelines."
        case .serious:
            return "Warning: High heat. Switch heavy tasks to Efficiency (E) cores or reduce Metal complexity."
        case .critical:
            return "Emergency: Immediate throttling. Halt non-essential processing, reduce display/GPU load."
        @unknown default:
            return "Monitor system integrity."
        }
    }
}
