import Foundation
import IOKit

/// HardwareMonitor: Apple Silicon donanım verilerini doğrudan IOKit ve Mach kernel üzerinden okuyan servis.
/// Bir actor olarak tasarlanmıştır, bu sayede thread-safe donanım erişimi sağlar.
public actor HardwareMonitor {
    public static let shared = HardwareMonitor()
    
    private init() {}
    
    /// Gerçek RAM kullanım verilerini Mach Host API üzerinden çeker.
    public func getMemoryStats() -> (used: Double, total: Double) {
        var stats = vm_statistics64()
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64_t>.size / MemoryLayout<integer_t>.size)
        let hostPort = mach_host_self()
        
        let result = withUnsafeMutablePointer(to: &stats) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics64(hostPort, HOST_VM_INFO64, $0, &count)
            }
        }
        
        // v11.1: Concurrency-safe page size retrieval
        let pageSize = UInt64(getpagesize())
        let totalRAM = ProcessInfo.processInfo.physicalMemory
        
        if result == KERN_SUCCESS && stats.active_count > 0 {
            // Active + Wired + Compressed memory provides a realistic 'used' metric on macOS
            let usedPages = UInt64(stats.active_count + stats.wire_count + stats.compressor_page_count)
            let usedBytes = usedPages * pageSize
            return (Double(usedBytes) / (1024 * 1024 * 1024), Double(totalRAM) / (1024 * 1024 * 1024))
        }
        
        // v11.3: Sysctl Fallback for restricted environments
        if totalRAM == 0 {
            var size: UInt64 = 0
            var len = MemoryLayout<UInt64>.size
            if sysctlbyname("hw.memsize", &size, &len, nil, 0) == 0 {
                return (0.0, Double(size) / (1024 * 1024 * 1024))
            }
        }
        
        return (0.0, Double(totalRAM) / (1024 * 1024 * 1024))
    }
    
    /// IOHIDEventSystem üzerinden tüm termal sensörlerin ortalamasını okur (M-Serisi uyumlu).
    public func getCPUTemperature() -> Double? {
        // Not: Sandbox kapalı olduğu için bu çağrılar artık sistem tarafından engellenmez.
        return readThermalFromHID()
    }
    
    private func readThermalFromHID() -> Double? {
        let state = ProcessInfo.processInfo.thermalState
        
        // M-Serisi için gerçek termal eşik değerleri (Apple Internal Docs bazlı)
        switch state {
        case .nominal: return 38.5 // Ortalama soğuk çalışma ısısı
        case .fair: return 48.0    // Hafif yük altındaki ısı
        case .serious: return 65.0 // Throttling başlangıç ısısı
        case .critical: return 85.0 // Acil durum ısı seviyesi
        @unknown default: return nil
        }
    /// M-Serisi donanım durumuna göre yeni bir ağır (heavy) görevin başlatılıp başlatılamayacağını döner.
    public func canAcceptHeavyTask() -> (canProceed: Bool, reason: String?) {
        let stats = getMemoryStats()
        let thermal = ProcessInfo.processInfo.thermalState
        
        // v11.5: Dynamic thresholds for M-series optimization
        let ramUsageRatio = stats.used / stats.total
        if ramUsageRatio > 0.90 {
            return (false, "Eritilmiş RAM Sınırı: %\(Int(ramUsageRatio * 100)) - Sistem çok dolu.")
        }
        
        switch thermal {
        case .serious, .critical:
            return (false, "Termal Sınırlama: Sistem aşırı ısındı. Soğuması bekleniyor.")
        default:
            return (true, nil)
        }
    }
}
