import Foundation

public actor ConfigManager {
    public static let shared = ConfigManager()
    
    private let fileManager = FileManager.default
    private let configURL: URL
    
    private var cachedConfig: InferenceConfig?
    
    private init() {
        self.configURL = PathConfiguration.shared.applicationSupportURL.appendingPathComponent("config.plist")
    }
    
    public func get() async -> InferenceConfig {
        if let cached = cachedConfig {
            return cached
        }
        
        if !fileManager.fileExists(atPath: configURL.path) {
            let defaultConfig = InferenceConfig.default
            await save(defaultConfig)
            self.cachedConfig = defaultConfig
            return defaultConfig
        }
        
        do {
            let data = try Data(contentsOf: configURL)
            let config = try PropertyListDecoder().decode(InferenceConfig.self, from: data)
            self.cachedConfig = config
            return config
        } catch {
            AgentLogger.logError("Error decoding config.plist, returning default. Error: \(error.localizedDescription)", agent: "Config")
            // Backup the corrupted file
            let backupURL = configURL.appendingPathExtension("bak")
            try? fileManager.moveItem(at: configURL, to: backupURL)
            
            let defaultConfig = InferenceConfig.default
            await save(defaultConfig)
            self.cachedConfig = defaultConfig
            return defaultConfig
        }
    }
    
    public func update(_ block: @Sendable (inout InferenceConfig) -> Void) async {
        var current = await get()
        block(&current)
        await save(current)
        self.cachedConfig = current
    }
    
    public func save(_ config: InferenceConfig) async {
        do {
            let encoder = PropertyListEncoder()
            encoder.outputFormat = .binary
            let data = try encoder.encode(config)
            try data.write(to: configURL)
        } catch {
            AgentLogger.logError("Failed to save config: \(error.localizedDescription)", agent: "Config")
        }
    }
}
