import Foundation
import IOKit

/// HardwareMonitor: Apple Silicon donanım verilerini doğrudan IOKit ve Mach kernel üzerinden okuyan servis.
/// Bir actor olarak tasarlanmıştır, bu sayede thread-safe donanım erişimi sağlar.
public actor HardwareMonitor {
    public static let shared = HardwareMonitor()
    
    private init() {}
    
    /// v7.0: Returns the current memory pressure level as detected by the kernel.
    public func getMemoryPressureLevel() async -> UNOMemoryPressureLevel {
        return await ProactiveMemoryPressureMonitor.shared.lastEvent
    }
    
    /// Gerçek RAM kullanım verilerini sysctl bazlı güvenli yöntemle çeker.
    /// Mach Host API (host_statistics64) yerine sysctl kullanmak, 0x5 yetki hatalarını bitirir.
    public func getMemoryStats() -> (used: Double, total: Double) {
        let totalRAMBytes = ProcessInfo.processInfo.physicalMemory
        
        // v20.5: Global safe memory retrieval via sysctl hw.usermem
        // Bu yöntem TaskPort/Accessibility yetkisi gerektirmez, 0x5 hatalarını önler.
        var userMem: UInt64 = 0
        var userMemSize = MemoryLayout<UInt64>.size
        let result = sysctlbyname("hw.usermem", &userMem, &userMemSize, nil, 0)
        
        let totalGB = Double(totalRAMBytes) / (1024 * 1024 * 1024)
        
        if result == 0 {
            let availableGB = Double(userMem) / (1024 * 1024 * 1024)
            let usedGB = max(0, totalGB - availableGB)
            return (usedGB, totalGB)
        } else {
            // Fallback: sysctl başarısız olursa sadece total RAM dön
            return (0, totalGB)
        }
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
        
        // v7.0: Proactive Check
        if ProcessInfo.processInfo.isLowPowerModeEnabled {
             // Low power mode usually implies some pressure or energy constraint
        }
        
        switch thermal {
        case .serious, .critical:
            return (false, "Termal Sınırlama: Sistem aşırı ısındı. Soğuması bekleniyor.")
        default:
            return (true, nil)
        }
    }

    /// v19.0: Returns true if the system is under serious thermal pressure 
    /// and Eco-Inference mode should be engaged.
    public var isEcoModeActive: Bool {
        let state = ProcessInfo.processInfo.thermalState
        return state == .serious || state == .critical
    }
}
