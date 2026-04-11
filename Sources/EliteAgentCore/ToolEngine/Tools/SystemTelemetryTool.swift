import Foundation
import AppKit

/// SystemTelemetryTool: EliteAgent'ın donanım farkındalığını (isı, bellek, CPU yükü) sağlayan çekirdek araç.
/// Bu araç sayesinde ajan, Apple Silicon mimarisinin o anki durumuna göre strateji belirleyebilir.
public struct SystemTelemetryTool: AgentTool {
    public let name = "get_system_telemetry"
    public let summary = "Monitor M-series thermal/RAM pressure."
    public let description = "Retrieve real-time hardware status including thermal state, memory pressure, and performance metrics."
    public let ubid = 36 // Token 'E' in Qwen 2.5
    
    public init() {}
    
    public func execute(params: [String: AnyCodable], session: Session) async throws -> String {
        let processInfo = ProcessInfo.processInfo
        
        // 1. Thermal State & Temperature
        let thermalState = processInfo.thermalState
        let currentTemp = await HardwareMonitor.shared.getCPUTemperature()
        let thermalDescription: String
        switch thermalState {
        case .nominal: thermalDescription = "Nominal (Cool) \(currentTemp != nil ? "- \(Int(currentTemp!))°C" : "")"
        case .fair: thermalDescription = "Fair (Normal) \(currentTemp != nil ? "- \(Int(currentTemp!))°C" : "")"
        case .serious: thermalDescription = "Serious (Throttling) \(currentTemp != nil ? "- \(Int(currentTemp!))°C" : "")"
        case .critical: thermalDescription = "Critical (Emergency) \(currentTemp != nil ? "- \(Int(currentTemp!))°C" : "")"
        @unknown default: thermalDescription = "Unknown"
        }
        
        // 2. Real Memory Usage (Mach Host API)
        let memoryStats = await HardwareMonitor.shared.getMemoryStats()
        
        // 3. System Load (Basic)
        let processorCount = processInfo.processorCount
        let activeProcessorCount = processInfo.activeProcessorCount
        let upTime = processInfo.systemUptime
        
        let report = "[TELEMETRY] Thermal:\(thermalDescription), Cores:\(activeProcessorCount)/\(processorCount), RAM:\(String(format: "%.1f", memoryStats.used))/\(String(format: "%.1f", memoryStats.total))GB, Uptime:\(Int(upTime / 3600))h, M-Series:\(isAppleSilicon())"
        
        return report
    }
    
    private func getSystemMemoryUsage() -> (used: Double, swap: Double) {
        // v9.0: Replaced by HardwareMonitor.shared.getMemoryStats()
        return (0.0, 0.0)
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
