import Foundation
import OSLog

/// Monitors Prompt Cache performance (v10.0 Titan) using os_signpost.
/// Triggers adaptive actions (like prefix shrinking) if hit rate drops below threshold.
public actor PromptCacheMonitor {
    public static let shared = PromptCacheMonitor()
    
    // v10.0: Unified Logging & Analytics
    private let logger = Logger(subsystem: "com.elite.agent", category: "CacheMonitor")
    private let signposter = OSSignposter(subsystem: "com.elite.agent", category: "PromptCache")
    
    private var history: [Bool] = []
    private let windowSize = 10
    private let threshold = 0.60
    
    private init() {}
    
    /// Records a cache event and evaluates hit rate.
    public func recordEvent(isHit: Bool) {
        let state = signposter.beginInterval("CacheProbe", id: signposter.makeSignpostID())
        defer { signposter.endInterval("CacheProbe", state, "Hit: \(isHit)") }
        
        history.append(isHit)
        if history.count > windowSize {
            history.removeFirst()
        }
        
        evaluatePerformance()
    }
    
    private func evaluatePerformance() {
        guard history.count >= 5 else { return }
        
        let hits = history.filter { $0 }.count
        let hitRate = Double(hits) / Double(history.count)
        
        if hitRate < threshold {
            logger.warning("Cache Hit Rate dropped to \(Int(hitRate * 100))%. Triggering Adaptive Action.")
            triggerAdaptiveAction()
        }
    }
    
    private func triggerAdaptiveAction() {
        // v10.0: Adaptive Response to Cache Inefficiency
        NotificationCenter.default.post(
            name: .promptCacheInefficiencyDetected,
            object: nil,
            userInfo: ["currentHitRate": history.filter { $0 }.count.description]
        )
    }
    
    public func getHitRate() -> Double {
        guard !history.isEmpty else { return 1.0 }
        return Double(history.filter { $0 }.count) / Double(history.count)
    }
}

extension Notification.Name {
    public static let promptCacheInefficiencyDetected = Notification.Name("app.eliteagent.promptCacheInefficiencyDetected")
}
