import Foundation
import Distributed

/// v13.0: EliteAgent Plugin Manager
/// Responsible for scanning and loading dynamic bundles from ~/Library/Application Support/EliteAgent/Plugins
public final class PluginManager: @unchecked Sendable {
    public static let shared = PluginManager()
    
    private let pluginsFolder: URL
    public private(set) var loadedPlugins: [String: any UNOToolPlugin] = [:]
    
    private init() {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        self.pluginsFolder = appSupport.appendingPathComponent("EliteAgent/Plugins", isDirectory: true)
        
        // Ensure directory exists
        try? FileManager.default.createDirectory(at: pluginsFolder, withIntermediateDirectories: true)
    }
    
    /// Scans the directory and loads all .bundle files
    public func scanAndLoad() -> [UNOToolSignature] {
        var signatures: [UNOToolSignature] = []
        
        guard let items = try? FileManager.default.contentsOfDirectory(at: pluginsFolder, includingPropertiesForKeys: nil) else {
            return []
        }
        
        for item in items where item.pathExtension == "bundle" {
            if let plugin = loadBundle(at: item) {
                let signature = plugin.signature
                loadedPlugins[signature.id] = plugin
                signatures.append(signature)
                AgentLogger.logInfo("[PluginManager] Loaded: \(signature.name) (\(signature.id))")
            }
        }
        
        return signatures
    }
    
    private func loadBundle(at url: URL) -> (any UNOToolPlugin)? {
        guard let bundle = Bundle(url: url), bundle.load() else {
            AgentLogger.logError("[PluginManager] Failed to load bundle at \(url.path)")
            return nil
        }
        
        // Use Principal Class approach
        guard let principalClass = bundle.principalClass as? NSObject.Type else {
            AgentLogger.logError("[PluginManager] No principal class in \(url.lastPathComponent)")
            return nil
        }
        
        let instance = principalClass.init()
        guard let plugin = instance as? any UNOToolPlugin else {
            AgentLogger.logError("[PluginManager] Principal class in \(url.lastPathComponent) does not conform to UNOToolPlugin")
            return nil
        }
        
        return plugin
    }
    
    public func executePlugin(id: String, action: UNOActionWrapper) async throws -> UNOResponse {
        guard let plugin = loadedPlugins[id] else {
            throw NSError(domain: "PluginManager", code: 404, userInfo: [NSLocalizedDescriptionKey: "Plugin \(id) not found"])
        }
        return try await plugin.execute(action: action)
    }
}


