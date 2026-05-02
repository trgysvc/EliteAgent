import os
import Foundation
import Distributed

/// v13.0: EliteAgent Plugin Manager
/// Responsible for scanning and loading dynamic bundles from ~/Library/Application Support/EliteAgent/Plugins
public final class PluginManager: Sendable {
    public static let shared = PluginManager()
    
    private let pluginsFolder: URL
    private let _loadedPlugins = OSAllocatedUnfairLock(initialState: [String: any UNOToolPlugin]())
    
    public var loadedPlugins: [String: any UNOToolPlugin] {
        _loadedPlugins.withLock { $0 }
    }
    
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
        _loadedPlugins.withLock { $0[signature.id] = plugin }
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
        let handle = dlopen(url.path, RTLD_NOW)
        guard let h = handle else {
            let error = String(cString: dlerror())
            AgentLogger.logError("[PluginManager] dlopen failed: \(error)")
            return nil
        }

        typealias CreatePluginFunc = @convention(c) () -> UnsafeMutableRawPointer?
        guard let symbol = dlsym(h, "createPlugin") else {
            dlclose(h)
            AgentLogger.logError("[PluginManager] No 'createPlugin' symbol found in \(url.lastPathComponent)")
            return nil
        }

        let f = unsafeBitCast(symbol, to: CreatePluginFunc.self)
        guard let ptr = f() else {
            dlclose(h)
            AgentLogger.logError("[PluginManager] createPlugin returned nil in \(url.lastPathComponent)")
            return nil
        }

        let plugin = Unmanaged<AnyObject>.fromOpaque(ptr).takeRetainedValue() as? any UNOToolPlugin
        if plugin == nil {
            dlclose(h)
            AgentLogger.logError("[PluginManager] Type mismatch: plugin does not conform to UNOToolPlugin in \(url.lastPathComponent)")
        }
        return plugin
    }
    
    public func executePlugin(id: String, action: UNOActionWrapper) async throws -> UNOResponse {
        let plugin = _loadedPlugins.withLock { $0[id] }
        guard let plugin = plugin else {
            throw NSError(domain: "PluginManager", code: 404, userInfo: [NSLocalizedDescriptionKey: "Plugin \(id) not found"])
        }
        return try await plugin.execute(action: action)
    }
}


