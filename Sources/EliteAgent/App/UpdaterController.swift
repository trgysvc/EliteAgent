import Foundation
import Sparkle
import EliteAgentCore

/// v7.1: Native Sparkle 2.x Updater Controller
/// Handles automated updates via the appcast.xml feed.
@MainActor
public final class UpdaterController: NSObject, ObservableObject {
    public static let shared = UpdaterController()
    
    private var updaterController: SPUStandardUpdaterController?
    
    @Published public var canCheckForUpdates = false
    
    private override init() {
        super.init()
        // Initialize the standard Sparkle updater controller.
        // The updater will start immediately and look for SUFeedURL in Info.plist.
        self.updaterController = SPUStandardUpdaterController(startingUpdater: true, updaterDelegate: nil, userDriverDelegate: nil)
        
        // v7.1: Bind the 'canCheckForUpdates' state to the updater's status.
        if let updater = updaterController?.updater {
            self.canCheckForUpdates = updater.canCheckForUpdates
        }
    }
    
    /// Explicitly triggers a check for updates, typically from a menu item or button.
    public func checkForUpdates() {
        AgentLogger.logAudit(level: .info, agent: "updater", message: "Manual update check triggered.")
        updaterController?.checkForUpdates(nil)
    }
}
