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
        
        // 2. Memory Usage (M-Series optimized via host_statistics64)
        let memoryStats = getSystemMemoryUsage()
        let totalRAM = Double(processInfo.physicalMemory) / (1024 * 1024 * 1024) // GB
        
        // 3. System Load (Basic)
        let processorCount = processInfo.processorCount
        let activeProcessorCount = processInfo.activeProcessorCount
        let upTime = processInfo.systemUptime
        
        let report = """
        [System Telemetry Report - Titan V3]
        - Thermal State: \(thermalDescription)
        - Processor Cores: \(processorCount) (Active: \(activeProcessorCount))
        - RAM Usage: \(String(format: "%.2f", memoryStats.used)) GB / \(String(format: "%.2f", totalRAM)) GB
        - System Uptime: \(Int(upTime / 3600)) hours
        - M-Series: \(isAppleSilicon() ? "Confirmed (ARM64)" : "Legacy Bridge")
        - Recommendations: \(getRecommendations(thermalState: thermalState))
        """
        
        return report
    }
    
    private func getSystemMemoryUsage() -> (used: Double, swap: Double) {
        let hostPort = mach_host_self()
        var hostSize = mach_msg_type_number_t(MemoryLayout<vm_statistics64_data_t>.size / MemoryLayout<integer_t>.size)
        var hostStats = vm_statistics64()
        
        // Safety Check: host_statistics64 can trigger 0x5 (KERN_PROTECTION_FAILURE) 
        // in certain hardened runtime configurations if task ports are restricted.
        let result = withUnsafeMutablePointer(to: &hostStats) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(hostSize)) {
                host_statistics64(hostPort, HOST_VM_INFO64, $0, &hostSize)
            }
        }
        
        if result != KERN_SUCCESS {
            // Handle 0x5 (KERN_PROTECTION_FAILURE) or other kern errors gracefully
            if result == 5 {
                AgentLogger.logAudit(level: .warn, agent: "guard", message: "System Telemetry: Mach-level memory stats restricted (Sandbox/0x5). Using fallback.")
            }
            return (0.0, 0.0)
        }
        
        var pageSize: vm_size_t = 0
        host_page_size(hostPort, &pageSize)
        let pageSize64 = UInt64(pageSize)
        
        let active = UInt64(hostStats.active_count) * pageSize64
        let wired = UInt64(hostStats.wire_count) * pageSize64
        let compressed = UInt64(hostStats.compressor_page_count) * pageSize64
        
        let usedGB = Double(active + wired + compressed) / (1024 * 1024 * 1024)
        return (usedGB, 0.0)
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
