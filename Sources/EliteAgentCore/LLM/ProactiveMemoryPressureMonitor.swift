import Foundation
import os

public actor ProactiveMemoryPressureMonitor {
    public static let shared = ProactiveMemoryPressureMonitor()

    private var source: DispatchSourceMemoryPressure?
    private(set) var lastEvent: DispatchSource.MemoryPressureEvent = []

    private let logger = Logger(subsystem: "app.eliteagent", category: "memorypressure")

    nonisolated private init() {}

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
        lastEvent = event

        let level: String
        if event.contains(.critical) {
            level = "CRITICAL"
            await OrchestratorRuntime.pauseAllSessions()
            await DreamActor.shared.forceConsolidate()
        } else if event.contains(.warning) {
            level = "WARNING"
            await OrchestratorRuntime.triggerCompaction()
        } else {
            level = "NORMAL"
            await OrchestratorRuntime.resumeAllSessions()
        }

        logger.warning("[Watchdog] 🔥 Proactive UMA Alert: Kernel Memory Pressure is \(level).")
    }

    deinit {
        source?.cancel()
    }
}
