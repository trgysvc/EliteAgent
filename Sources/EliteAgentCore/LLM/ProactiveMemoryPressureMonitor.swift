import Foundation
import os

public enum UNOMemoryPressureLevel: String, Sendable {
    case normal
    case warning
    case critical
}

extension Notification.Name {
    public static let memoryPressureChanged = Notification.Name("com.elite.agent.memoryPressureChanged")
}

public actor ProactiveMemoryPressureMonitor {
    public static let shared = ProactiveMemoryPressureMonitor()

    private var source: DispatchSourceMemoryPressure?
    private(set) var lastEvent: UNOMemoryPressureLevel = .normal

    private let logger = Logger(subsystem: "app.eliteagent", category: "memorypressure")

    private init() {}

    public func startMonitoring() async {
        // Create dispatch source on main queue to ensure serial event delivery
        let source = DispatchSource.makeMemoryPressureSource(eventMask: [.all], queue: .main)
        self.source = source

        // Bridge GCD callback to async/await
        source.setEventHandler { [weak self] in
            guard let self = self else { return }
            Task {
                let event = source.data
                await self.handlePressure(event)
            }
        }

        source.resume()
        logger.info("[Watchdog] Proactive Memory Pressure Monitor started and listening.")
    }

    private func handlePressure(_ event: DispatchSource.MemoryPressureEvent) async {
        let level: UNOMemoryPressureLevel
        if event.contains(.critical) {
            level = .critical
            OrchestratorRuntime.pauseAllSessions()
            await DreamActor.shared.forceConsolidate()
        } else if event.contains(.warning) {
            level = .warning
            OrchestratorRuntime.triggerCompaction()
        } else {
            level = .normal
            OrchestratorRuntime.resumeAllSessions()
        }
        
        lastEvent = level
        NotificationCenter.default.post(name: .memoryPressureChanged, object: level)
        logger.warning("[Watchdog] 🔥 Proactive UMA Alert: Kernel Memory Pressure is \(level.rawValue).")
    }

    deinit {
        source?.cancel()
    }
}
