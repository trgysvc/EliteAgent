import Foundation
import OSLog

/// v27.0: Trajectory Recorder (Observability & Determinism)
/// Records every step of a session into a structured binary format.
/// Enables session replay, failure analysis, and analytical auditing.
public actor TrajectoryRecorder {
    
    // MARK: - Types
    
    public enum TrajectoryEvent: Codable, Sendable {
        case userMessage(content: String, timestamp: Date)
        case assistantMessage(content: String, timestamp: Date)
        case toolCall(name: String, ubid: Int128, params: [String: AnyCodable], timestamp: Date)
        case toolResult(name: String, ubid: Int128, result: String, durationMs: Int, timestamp: Date)
        case compaction(tokensBefore: Int, tokensAfter: Int, timestamp: Date)
        case loopDetected(detector: String, count: Int, timestamp: Date)
        case evidenceGuardVeto(reason: String, timestamp: Date)
        case contextGuard(usedTokens: Int, maxTokens: Int, action: String, timestamp: Date)
        case hardwareSnapshot(ramUsedGB: Double, thermalState: Int, timestamp: Date)
    }
    
    // MARK: - State
    
    private let sessionId: UUID
    private var events: [TrajectoryEvent] = []
    private let fileURL: URL
    private let logger = Logger(subsystem: "com.elite.agent", category: "Trajectory")
    
    public init(sessionId: UUID) {
        self.sessionId = sessionId
        self.fileURL = PathConfiguration.shared.trajectoriesURL.appendingPathComponent("\(sessionId.uuidString).traj")
        
        // Initial snapshot
        Task {
            await record(.hardwareSnapshot(
                ramUsedGB: await HardwareMonitor.shared.getMemoryStats().used,
                thermalState: ProcessInfo.processInfo.thermalState.rawValue,
                timestamp: Date()
            ))
        }
    }
    
    // MARK: - Public API
    
    /// Records a new event to the trajectory.
    public func record(_ event: TrajectoryEvent) {
        events.append(event)
        
        // Periodic auto-save (every 5 events)
        if events.count % 5 == 0 {
            saveToDisk()
        }
    }
    
    /// Finalizes the recording and saves the complete trajectory to disk.
    public func finalize() throws -> URL {
        saveToDisk()
        logger.info("Trajectory finalized for session \(self.sessionId.uuidString)")
        return fileURL
    }
    
    /// Returns the current list of events.
    public func getEvents() -> [TrajectoryEvent] {
        return events
    }
    
    // MARK: - Private
    
    private func saveToDisk() {
        do {
            let encoder = PropertyListEncoder()
            encoder.outputFormat = .binary
            let data = try encoder.encode(events)
            try data.write(to: fileURL, options: .atomic)
        } catch {
            logger.error("Failed to save trajectory: \(error.localizedDescription)")
        }
    }
}
