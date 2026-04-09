import Foundation
import Metal

public enum HealthStatus: Equatable, Sendable {
    case healthy
    case lowMemory(availableMB: Int)
    case criticalPressure
    case metalUnsupported
    case portBusy(Int)
    case modelFilesMissing
    case corruptedHeader
    case unknown(String)
    
    public var displayString: String {
        switch self {
        case .healthy: return "Healthy"
        case .lowMemory(let mb): return "Düşük Bellek (\(mb) MB Boş)"
        case .criticalPressure: return "Kritik Bellek Baskısı (Sistem Çok Yoğun)"
        case .metalUnsupported: return "Metal Birimi Desteklenmiyor"
        case .portBusy(let p): return "Port Meşgul: \(p)"
        case .modelFilesMissing: return "Model Dosyaları Eksik"
        case .corruptedHeader: return "Dosya Başlığı Bozuk"
        case .unknown(let s): return "Bilinmeyen Hata: \(s)"
        }
    }
}

public actor LocalModelHealthMonitor {
    public static let shared = LocalModelHealthMonitor()
    
    // v7.8.5 PVP Debug Hooks
    private var debugPressureOverride: HealthStatus? = nil
    
    public func setDebugOverride(_ status: HealthStatus?) {
        self.debugPressureOverride = status
    }
    
    private init() {}
    
    public func runDiagnostics(modelID: String?) async -> HealthStatus {
        guard let modelID = modelID, !modelID.isEmpty else {
            return .modelFilesMissing
        }
        
        // PVP Override check
        if let override = self.debugPressureOverride {
            return override
        }
        
        // 1. Metal Check
        guard MTLCreateSystemDefaultDevice() != nil else {
            return .metalUnsupported
        }
        
        // 2. Unified Memory Diagnostics (v7.8.5)
        let diag = await diagnoseMemory()
        if diag.pressureLevel == .critical {
            return .criticalPressure
        }
        
        let mbFree = Int(Int64(diag.availableBytes) / (1024 * 1024))
        if mbFree < 1500 { // Reduced from 3.5GB to 1.5GB
            return .lowMemory(availableMB: mbFree)
        }
        
        // 3. Basic File Existence Check
        var path = await ModelSetupManager.shared.getModelDirectory(for: modelID)
        
        // v7.8.6 Robust Fallback: Check both Instruct and non-Instruct variants
        if !FileManager.default.fileExists(atPath: path.path) {
            let altID: String
            if modelID.contains("-Instruct") {
                altID = modelID.replacingOccurrences(of: "-Instruct", with: "")
            } else if modelID.contains("2.5-7B") {
                altID = modelID.replacingOccurrences(of: "2.5-7B", with: "2.5-7B-Instruct")
            } else if modelID.contains("3.5-9B") {
                altID = modelID.replacingOccurrences(of: "3.5-9B", with: "3.5-9B-Instruct")
            } else {
                altID = modelID + "-Instruct"
            }
            
            let altPath = await ModelSetupManager.shared.getModelDirectory(for: altID)
            if !FileManager.default.fileExists(atPath: altPath.path) {
                return .modelFilesMissing
            }
            path = altPath
        }
        
        return .healthy
    }
    
    private func isPortAvailable(_ port: Int) -> Bool {
        var addr = sockaddr_in()
        addr.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        addr.sin_family = sa_family_t(AF_INET)
        addr.sin_port = UInt16(port).bigEndian
        addr.sin_addr.s_addr = inet_addr("127.0.0.1")
        
        let fd = socket(AF_INET, SOCK_STREAM, 0)
        guard fd != -1 else { return false }
        defer { close(fd) }
        
        let result = connect(fd, withUnsafePointer(to: &addr) { $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { $0 } }, socklen_t(MemoryLayout<sockaddr_in>.size))
        return result != 0 
    }

    private struct MemoryDiagnostics {
        let availableBytes: UInt64
        let pressureLevel: PressureLevel
        enum PressureLevel { case normal, warning, critical, unknown }
    }

    private func diagnoseMemory() async -> MemoryDiagnostics {
        // v11.0: Using HardwareMonitor for real Mach Host statistics
        let stats = await HardwareMonitor.shared.getMemoryStats()
        let availableBytes = UInt64((stats.total - stats.used) * 1024 * 1024 * 1024)
        
        let processInfo = ProcessInfo.processInfo
        let state = processInfo.thermalState
        
        // Termal durum ve bellek baskısını birleştirerek gerçek bir risk seviyesi belirliyoruz
        let pressureLevel: MemoryDiagnostics.PressureLevel
        if state == .critical || state == .serious {
            pressureLevel = .critical
        } else if stats.used / stats.total > 0.85 {
            pressureLevel = .warning
        } else {
            pressureLevel = .normal
        }
        
        return MemoryDiagnostics(availableBytes: availableBytes, pressureLevel: pressureLevel)
    }
}
