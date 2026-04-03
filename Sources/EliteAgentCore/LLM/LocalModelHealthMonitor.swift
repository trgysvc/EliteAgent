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
    
    public func runDiagnostics(modelID: String) async -> HealthStatus {
        // PVP Override check
        if let override = self.debugPressureOverride {
            return override
        }
        
        // 1. Metal Check
        guard MTLCreateSystemDefaultDevice() != nil else {
            return .metalUnsupported
        }
        
        // 2. Unified Memory Diagnostics (v7.8.5)
        let diag = diagnoseMemory()
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

    private func diagnoseMemory() -> MemoryDiagnostics {
        // For macOS, host_statistics64 is the primary way to get system-wide memory.
        var stats = vm_statistics64_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64_data_t>.size / MemoryLayout<integer_t>.size)
        let kr = withUnsafeMutablePointer(to: &stats) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &count)
            }
        }
        
        guard kr == KERN_SUCCESS else { 
            return MemoryDiagnostics(availableBytes: 0, pressureLevel: .unknown) 
        }
        
        // Safe conversion to Int64 to avoid "Negative value is not representable" crashes
        let ps = Int64(getpagesize())
        let freePages = Int64(stats.free_count)
        let purgePages = Int64(stats.purgeable_count)
        let inactivePages = Int64(stats.inactive_count)
        let specPages = Int64(stats.speculative_count)
        let compPages = Int64(stats.compressor_page_count)
        let activePages = Int64(stats.active_count)
        
        let available = max(0, freePages + purgePages + inactivePages + specPages) * ps
        let pressureRatio = Double(max(0, compPages)) / Double(max(1, activePages + compPages))
        
        let level: MemoryDiagnostics.PressureLevel = pressureRatio > 0.95 ? .critical : (pressureRatio > 0.6 ? .warning : .normal)
        return MemoryDiagnostics(availableBytes: UInt64(available), pressureLevel: level)
    }
}
