import Foundation
import AppKit

/// SystemTelemetryTool: EliteAgent'ın donanım farkındalığını (isı, bellek, CPU yükü) sağlayan çekirdek araç.
/// Bu araç sayesinde ajan, Apple Silicon mimarisinin o anki durumuna göre strateji belirleyebilir.
public struct SystemTelemetryTool: AgentTool {
    public let name = "get_system_telemetry"
    public let summary = "Monitor M-series thermal/RAM pressure."
    public let description = "Retrieve real-time hardware status including thermal state, free memory, active cores, and performance metrics. Use this for ALL CPU, RAM, memory, and hardware queries."
    public let ubid = 36 // Token 'E' in Qwen 2.5
    
    public init() {}
    
    public func execute(params: [String: AnyCodable], session: Session) async throws -> String {
        let processInfo = ProcessInfo.processInfo
        
        // 1. Thermal State
        let thermalState = processInfo.thermalState
        let thermalDescription: String
        switch thermalState {
        case .nominal:  thermalDescription = "✅ Soğuk (Nominal)"
        case .fair:     thermalDescription = "🟡 Normal (Fair)"
        case .serious:  thermalDescription = "🟠 Throttling (Serious)"
        case .critical: thermalDescription = "🔴 Kritik (Critical)"
        @unknown default: thermalDescription = "Bilinmiyor"
        }
        
        // 2. Real Memory Usage via Mach Host API (no shell required)
        let memStats = await HardwareMonitor.shared.getMemoryStats()
        let totalGB  = memStats.total
        let usedGB   = memStats.used
        let freeGB   = max(0, totalGB - usedGB)
        let usagePct = totalGB > 0 ? Int((usedGB / totalGB) * 100) : 0

        // 3. CPU Core Info
        let activeCores = processInfo.activeProcessorCount
        let totalCores  = processInfo.processorCount
        
        // 4. Uptime
        let uptimeHours = Int(processInfo.systemUptime / 3600)
        let uptimeMins  = Int((processInfo.systemUptime.truncatingRemainder(dividingBy: 3600)) / 60)
        
        // 5. OS Version
        let osVersion = processInfo.operatingSystemVersionString
        
        let report = """
        [🖥 Sistem Telemetri Raporu]
        ─────────────────────────────
        • İşletim Sistemi : macOS (\(osVersion))
        • Termal Durum   : \(thermalDescription)
        • CPU Çekirdek   : \(activeCores) aktif / \(totalCores) toplam
        • Toplam RAM     : \(String(format: "%.1f", totalGB)) GB
        • Kullanılan RAM : \(String(format: "%.1f", usedGB)) GB (%\(usagePct))
        • Boş RAM        : \(String(format: "%.1f", freeGB)) GB
        • Sistem Süresi  : \(uptimeHours) saat \(uptimeMins) dakika
        • Mimari         : Apple Silicon (M-Serisi, arm64)
        ─────────────────────────────
        [SystemDNA_WIDGET] { "os": "\(osVersion)", "thermal": "\(thermalState.rawValue)", "cpu": "\(activeCores)/\(totalCores)", "ram_total": \(totalGB), "ram_used": \(usedGB), "ram_pct": \(usagePct), "uptime": "\(uptimeHours)h \(uptimeMins)m" }
        """
        
        return report
    }
    
    private func isAppleSilicon() -> Bool {
        #if arch(arm64)
        return true
        #else
        return false
        #endif
    }
}
