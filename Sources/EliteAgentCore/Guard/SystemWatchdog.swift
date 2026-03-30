import Foundation

/// Monitors system health and triggers graceful degradation if hardware limits are reached.
/// (Titan Adaptive Telemetry Engine)
public actor SystemWatchdog {
    public static let shared = SystemWatchdog()
    
    public private(set) var thermalState: ProcessInfo.ThermalState = .nominal
    
    private init() {
        // Swift 6: Initialization must be synchronous, but monitoring setup 
        // involves actor-isolated state, so we wrap in a Task.
        Task {
            await setupMonitoring()
        }
    }
    
    private func setupMonitoring() {
        // 1. Thermal Monitoring
        NotificationCenter.default.addObserver(
            forName: ProcessInfo.thermalStateDidChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task {
                await self?.updateThermalState()
            }
        }
        
        // 2. Memory Pressure Monitoring
        let source = DispatchSource.makeMemoryPressureSource(eventMask: [.warning, .critical], queue: .global())
        source.setEventHandler { [weak self, weak source] in
            guard let event = source?.data else { return }
            let rawValue = event.rawValue
            Task {
                await self?.handleMemoryPressure(rawValue: rawValue)
            }
        }
        source.resume()
    }
    
    private func updateThermalState() {
        let newState = ProcessInfo.processInfo.thermalState
        self.thermalState = newState
        
        AgentLogger.logAudit(level: .info, agent: "guard", message: "Thermal state changed to: \(newState)")
        
        if newState == .serious || newState == .critical {
            // Signal to InferenceActor to reduce point cloud density or precision
            Task {
                await InferenceActor.shared.clearCache()
            }
        }
    }
    
    private func handleMemoryPressure(rawValue: UInt) {
        AgentLogger.logAudit(level: .warn, agent: "guard", message: "Memory pressure detected (Raw: \(rawValue))")
        
        Task {
            await InferenceActor.shared.clearCache()
        }
    }
}

// Swift 6: Conformance to external protocols must be explicit or retroactive
extension ProcessInfo.ThermalState: @retroactive CustomStringConvertible {
    public var description: String {
        switch self {
        case .nominal: return "Nominal"
        case .fair: return "Fair"
        case .serious: return "Serious"
        case .critical: return "Critical"
        @unknown default: return "Unknown"
        }
    }
}
