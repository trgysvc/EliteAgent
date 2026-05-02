import Foundation

/// UpdaterService is a stub in EliteAgentCore.
/// The real Sparkle-dependent implementation lives in the main App target (EliteAgent)
/// because Sparkle.framework is only linked to the App, not the static Core library.
public final class UpdaterService: @unchecked Sendable {
    public static let shared = UpdaterService()
    private init() {}
    
    /// Called by App target's concrete UpdaterService via notification or direct call.
    /// No-op in Core — prevents Core from depending on Sparkle.
    public func checkForUpdates() {
        AgentLogger.logInfo("checkForUpdates() — Core stub. Use UpdaterController in App target.", agent: "Updater")
    }
}
