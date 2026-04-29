import Foundation
import OSLog

/// v27.0: Subagent Registry (OpenClaw-Inspired Lifecycle Management)
/// Tracks all active sub-runtimes to prevent orphan processes and enable global control.
public actor SubagentRegistry {
    public static let shared = SubagentRegistry()
    
    private var activeSubagents: [UUID: OrchestratorRuntime] = [:]
    private let logger = Logger(subsystem: "com.elite.agent", category: "SubagentRegistry")
    
    private init() {}
    
    /// Registers an active subagent runtime.
    public func register(id: UUID, runtime: OrchestratorRuntime) {
        activeSubagents[id] = runtime
        logger.info("Registered subagent: \(id.uuidString). Total active: \(self.activeSubagents.count)")
    }
    
    /// Unregisters a completed or failed subagent runtime.
    public func unregister(id: UUID) {
        activeSubagents.removeValue(forKey: id)
        logger.info("Unregistered subagent: \(id.uuidString). Remaining: \(self.activeSubagents.count)")
    }
    
    /// Interrupts all active subagents (e.g., during parent termination or emergency stop).
    public func interruptAll() async {
        logger.warning("Interrupting all \(self.activeSubagents.count) active subagents...")
        for (id, runtime) in activeSubagents {
            await runtime.interrupt()
            logger.info("Interrupted subagent: \(id.uuidString)")
        }
        activeSubagents.removeAll()
    }
    
    /// Returns the number of currently active subagents.
    public func getActiveCount() -> Int {
        return activeSubagents.count
    }
}
