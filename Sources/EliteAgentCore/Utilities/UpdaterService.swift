import Foundation
import Sparkle

public final class UpdaterService: NSObject, SPUUpdaterDelegate, Sendable {
    public static let shared = UpdaterService()
    
    private var updater: SPUStandardUpdaterController?
    
    private override init() {
        super.init()
        // Initialize Sparkle SPUStandardUpdaterController
        self.updater = SPUStandardUpdaterController(startingUpdater: true, updaterDelegate: self, userDriverDelegate: nil)
    }
    
    public func checkForUpdates() {
        print("[UPDATER]: Checking for new EliteAgent releases...")
        updater?.updater.checkForUpdates()
    }
    
    public func updater(_ updater: SPUUpdater, didFindValidUpdate item: SUAppcastItem) {
        print("[UPDATER]: Found new version: \(item.displayVersionString)")
    }
    
    public func updaterDidNotFindUpdate(_ updater: SPUUpdater) {
        print("[UPDATER]: EliteAgent is already at the latest version.")
    }
    
    // Auto-update logic (Silent) - configure in Info.plist (SUAllowsAutomaticUpdates)
}
