import Foundation

public actor ConfigManager {
    public static let shared = ConfigManager()
    
    private let fileManager = FileManager.default
    private let configURL: URL
    
    private var cachedConfig: InferenceConfig?
    
    private init() {
        let home = fileManager.homeDirectoryForCurrentUser
        let eliteDir = home.appendingPathComponent(".eliteagent")
        self.configURL = eliteDir.appendingPathComponent("config.json")
        
        // Ensure directory exists
        try? fileManager.createDirectory(at: eliteDir, withIntermediateDirectories: true)
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
            let config = try JSONDecoder().decode(InferenceConfig.self, from: data)
            self.cachedConfig = config
            return config
        } catch {
            print("[CONFIG] Error decoding config.json, returning default. Error: \(error)")
            // Backup the corrupted file
            let backupURL = configURL.appendingPathExtension("bak")
            try? fileManager.moveItem(at: configURL, to: backupURL)
            
            let defaultConfig = InferenceConfig.default
            await save(defaultConfig)
            self.cachedConfig = defaultConfig
            return defaultConfig
        }
    }
    
    public func update(_ block: (inout InferenceConfig) -> Void) async {
        var current = await get()
        block(&current)
        await save(current)
        self.cachedConfig = current
    }
    
    private func save(_ config: InferenceConfig) async {
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = .prettyPrinted
            let data = try encoder.encode(config)
            try data.write(to: configURL)
        } catch {
            print("[CONFIG] Failed to save config: \(error)")
        }
    }
}
