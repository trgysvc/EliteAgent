import Foundation
import os.log
import MetricKit

/// v10.1: Local-only, privacy-first telemetry manager.
/// Focuses on "Setup Wizard Effort" and "None-state Duration" to improve onboarding UX.
public actor UXTelemetryManager {
    public static let shared = UXTelemetryManager()
    
    private let logger = Logger(subsystem: "com.eliteagent.core", category: "UXTelemetry")
    private var sessionID: UUID = UUID()
    private var noneStateStartTime: Date?
    private var wizardInteractions: Int = 0
    
    private init() {}
    
    /// Starts tracking the duration the user spends in the .none state (no model selected).
    public func startNoneStateTracking() {
        if noneStateStartTime == nil {
            noneStateStartTime = Date()
            logger.info("None-state tracking started. Session: \(self.sessionID.uuidString)")
        }
    }
    
    /// Stops tracking none-state and logs the total duration locally.
    public func stopNoneStateTracking() {
        guard let start = noneStateStartTime else { return }
        let duration = Date().timeIntervalSince(start)
        logger.info("None-state ended. Duration: \(duration)s")
        noneStateStartTime = nil
        
        // Log locally for aggregate local analysis
        logger.info("MXPayload Logged: NoneStateDuration: \(Int(duration))s")
    }
    
    /// Records a setup wizard interaction (button click, page skip).
    public func recordWizardInteraction(action: String) {
        wizardInteractions += 1
        logger.debug("Wizard interaction: \(action) (Count: \(self.wizardInteractions))")
    }
    
    /// Resets the session ID for a fresh tracking period.
    public func resetSession() {
        self.sessionID = UUID()
        self.noneStateStartTime = nil
        self.wizardInteractions = 0
    }
}
