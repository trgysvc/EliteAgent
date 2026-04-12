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
    
    /// Scans the directory and loads all .bundle and .dylib files
    public func scanAndLoad() -> [UNOToolSignature] {
        var signatures: [UNOToolSignature] = []
        
        guard let items = try? FileManager.default.contentsOfDirectory(at: pluginsFolder, includingPropertiesForKeys: nil) else {
            return []
        }
        
        for item in items {
            if item.pathExtension == "bundle" {
                if let plugin = loadBundle(at: item) {
                    registerPlugin(plugin, signatures: &signatures)
                }
            } else if item.pathExtension == "dylib" {
                if let plugin = loadDylib(at: item) {
                    registerPlugin(plugin, signatures: &signatures)
                }
            }
        }
        
        return signatures
    }
    
    private func registerPlugin(_ plugin: any UNOToolPlugin, signatures: inout [UNOToolSignature]) {
        let signature = plugin.signature
        loadedPlugins[signature.id] = plugin
        signatures.append(signature)
        AgentLogger.logInfo("[PluginManager] Loaded: \(signature.name) (\(signature.id))")
    }
    
    private func loadBundle(at url: URL) -> (any UNOToolPlugin)? {
        guard let bundle = Bundle(url: url), bundle.load() else {
            AgentLogger.logError("[PluginManager] Failed to load bundle at \(url.path)")
            return nil
        }
        
        guard let principalClass = bundle.principalClass as? NSObject.Type else {
            AgentLogger.logError("[PluginManager] No principal class in \(url.lastPathComponent)")
            return nil
        }
        
        let instance = principalClass.init()
        return instance as? any UNOToolPlugin
    }
    
    private func loadDylib(at url: URL) -> (any UNOToolPlugin)? {
        // v14.5: Dynamic Library Loading (dlopen)
        let handle = dlopen(url.path, RTLD_NOW)
        guard let h = handle else {
            let error = String(cString: dlerror())
            AgentLogger.logError("[PluginManager] dlopen failed: \(error)")
            return nil
        }
        
        // v14.6: C-Entry Point lookup for Swift initialization
        // We look for a mangled symbol or a stable C-entry point.
        // For EliteAgent, we expect a 'createPlugin' function.
        typealias CreatePluginFunc = @convention(c) () -> UnsafeMutableRawPointer?
        if let symbol = dlsym(h, "createPlugin") {
            let f = unsafeBitCast(symbol, to: CreatePluginFunc.self)
            if let ptr = f() {
                // Re-cast the pointer back to our protocol
                // This is a high-level bridge between the raw dylib and Swift.
                let plugin = Unmanaged<AnyObject>.fromOpaque(ptr).takeRetainedValue() as? any UNOToolPlugin
                return plugin
            }
        } else {
            AgentLogger.logError("[PluginManager] No 'createPlugin' symbol found in \(url.lastPathComponent)")
        }
        
        return nil
    }
    
    public func executePlugin(id: String, action: UNOActionWrapper) async throws -> UNOResponse {
        guard let plugin = loadedPlugins[id] else {
            throw NSError(domain: "PluginManager", code: 404, userInfo: [NSLocalizedDescriptionKey: "Plugin \(id) not found"])
        }
        return try await plugin.execute(action: action)
    }
}


