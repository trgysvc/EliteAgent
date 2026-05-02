import Foundation

public struct BrowserConfig: Codable, Sendable {
    public let allowedDomains: [String]
}

public struct VaultInferenceConfig: Codable, Sendable {
    public let pauseOnUserInteraction: Bool?
}

public struct MCPServerConfig: Codable, Sendable {
    public let name: String
    public let command: String
    public let args: [String]
    public let env: [String: String]?
    
    public init(name: String, command: String, args: [String], env: [String: String]? = nil) {
        self.name = name
        self.command = command
        self.args = args
        self.env = env
    }
}

public struct VaultConfig: Codable, Sendable {
    public let providers: [ProviderConfig]
    public let routingStrategy: RoutingStrategy
    public let inference: VaultInferenceConfig?
    public let browser: BrowserConfig?
    public let mcpServers: [MCPServerConfig]?
    
    public init(providers: [ProviderConfig], routingStrategy: RoutingStrategy, inference: VaultInferenceConfig?, browser: BrowserConfig?, mcpServers: [MCPServerConfig]? = nil) {
        self.providers = providers
        self.routingStrategy = routingStrategy
        self.inference = inference
        self.browser = browser
        self.mcpServers = mcpServers
    }
}

public struct ProviderConfig: Codable, Sendable {
    public let id: String
    public let type: ProviderType
    public let endpoint: String?
    public let keychainKey: String?
    public let modelName: String?
    public let capabilities: [String]?
    public let costPer1KTokens: Double?
    public let promptPrice: Double?
    public let completionPrice: Double?
    public let maxContextTokens: Int?
    public let temperature: Double?
    public let topP: Double?
    public let maxTokens: Int?
    
    public init(id: String, type: ProviderType, endpoint: String?, keychainKey: String?, modelName: String?, capabilities: [String]?, costPer1KTokens: Double?, promptPrice: Double?, completionPrice: Double?, maxContextTokens: Int?, temperature: Double?, topP: Double?, maxTokens: Int?) {
        self.id = id
        self.type = type
        self.endpoint = endpoint
        self.keychainKey = keychainKey
        self.modelName = modelName
        self.capabilities = capabilities
        self.costPer1KTokens = costPer1KTokens
        self.promptPrice = promptPrice
        self.completionPrice = completionPrice
        self.maxContextTokens = maxContextTokens
        self.temperature = temperature
        self.topP = topP
        self.maxTokens = maxTokens
    }
}


public enum RoutingStrategy: String, Codable, Sendable {
    case localFirst = "local_first"
    case cloudOnly = "cloud_only"
    case hybrid = "hybrid"
}

public enum VaultError: Error, CustomStringConvertible, Sendable {
    case fileNotFound(URL)
    case unreadablePath
    case invalidFormat(Error)
    case missingKeychainResource(keychainKey: String)
    case apiTokenReadFailed(String)
    
    public var description: String {
        switch self {
        case .fileNotFound(let url): return "Vault plist not found at \(url.path)."
        case .unreadablePath: return "Vault plist path is invalid or unreadable."
        case .invalidFormat(let error): return "Failed to decode vault.plist: \(error)"
        case .missingKeychainResource(let keychainKey): return "API Key missing from Keychain for identifier: \(keychainKey)"
        case .apiTokenReadFailed(let error): return "Failed to read API Key: \(error)"
        }
    }
}

public actor VaultManager {
    @MainActor public static var shared: VaultManager!
    
    public nonisolated let config: VaultConfig
    private let configURL: URL
    private let keychain = KeychainHelper()
    
    public init(configURL: URL) throws {
        self.configURL = configURL
        let folderURL = configURL.deletingLastPathComponent()
        
        // Ensure folder exists
        if !FileManager.default.fileExists(atPath: folderURL.path) {
            try FileManager.default.createDirectory(at: folderURL, withIntermediateDirectories: true)
        }
        
        // Ensure file exists or create default
        if !FileManager.default.fileExists(atPath: configURL.path) {
            AgentLogger.logInfo("Config missing at \(configURL.path). Creating default...", agent: "VaultManager")
            let defaultConfig = VaultConfig(
                providers: [
                    ProviderConfig(id: "mlx", type: .local, endpoint: nil, keychainKey: nil, modelName: "", capabilities: ["reasoning", "tools", "code"], costPer1KTokens: 0, promptPrice: 0, completionPrice: 0, maxContextTokens: 32768, temperature: 0.7, topP: 1.0, maxTokens: 4096),
                    ProviderConfig(id: "openrouter", type: .cloud, endpoint: "https://openrouter.ai/api/v1", keychainKey: "OPENROUTER_API_KEY", modelName: "", capabilities: ["vision", "tools"], costPer1KTokens: nil, promptPrice: nil, completionPrice: nil, maxContextTokens: 200000, temperature: 0.7, topP: 1.0, maxTokens: 4096)
                ],
                routingStrategy: .localFirst,
                inference: VaultInferenceConfig(pauseOnUserInteraction: true),
                browser: BrowserConfig(allowedDomains: ["github.com", "google.com", "apple.com"]),
                mcpServers: []
            )
            let encoder = PropertyListEncoder()
            encoder.outputFormat = .xml
            let defaultData = try encoder.encode(defaultConfig)
            try defaultData.write(to: configURL)
        }
        
        do {
            let data = try Data(contentsOf: configURL)
            let decoder = PropertyListDecoder()
            var decodedConfig: VaultConfig
            
            do {
                decodedConfig = try decoder.decode(VaultConfig.self, from: data)
            } catch {
                AgentLogger.logAudit(level: .warn, agent: "VaultManager", message: "⚠️ SCHEMA MISMATCH DETECTED: \(error.localizedDescription)")
                AgentLogger.logInfo("Attempting surgical healing (preserving model selection)...", agent: "VaultManager")
                
                // v19.7.3: Surgical Extraction
                var preservedModelName = ""
                if let dict = try? PropertyListSerialization.propertyList(from: data, options: [], format: nil) as? [String: Any],
                   let providers = dict["providers"] as? [[String: Any]] {
                    if let mlx = providers.first(where: { ($0["id"] as? String) == "mlx" }) {
                        preservedModelName = mlx["modelName"] as? String ?? ""
                    }
                }
                
                decodedConfig = VaultManager.createDefaultConfig(initialModelName: preservedModelName)
                let encoder = PropertyListEncoder()
                encoder.outputFormat = .xml
                let healedData = try encoder.encode(decodedConfig)
                try healedData.write(to: configURL)
                
                AgentLogger.logAudit(level: .info, agent: "VaultManager", message: "✅ SURGICAL HEALING COMPLETE: Legacy artifacts purged, model selection '\(preservedModelName)' preserved.")
            }
            
            // Sync required providers to ensure migration completeness
            var wasRestored = try VaultManager.syncRequiredProviders(config: &decodedConfig, configURL: configURL)
            
            // v19.7.4 Auto-Priming: If local model is empty, try to discover one on disk
            let autoPrimed = try VaultManager.autoPrimeModelIfEmpty(config: &decodedConfig, configURL: configURL)
            wasRestored = wasRestored || autoPrimed
            
            self.config = decodedConfig
            
            if wasRestored {
                AgentLogger.logInfo("Successfully restored missing required providers or auto-primed models.", agent: "VaultManager")
            }
        } catch {
            // Last resort: If healing itself fails, we throw to alert Orchestrator
            throw VaultError.invalidFormat(error)
        }
    }
    
    private static func createDefaultConfig(initialModelName: String = "") -> VaultConfig {
        return VaultConfig(
            providers: [
                ProviderConfig(id: "mlx", type: .local, endpoint: nil, keychainKey: nil, modelName: initialModelName, capabilities: ["reasoning", "tools", "code"], costPer1KTokens: 0, promptPrice: 0, completionPrice: 0, maxContextTokens: 32768, temperature: 0.7, topP: 1.0, maxTokens: 4096),
                ProviderConfig(id: "openrouter", type: .cloud, endpoint: "https://openrouter.ai/api/v1", keychainKey: "OPENROUTER_API_KEY", modelName: "", capabilities: ["vision", "tools"], costPer1KTokens: nil, promptPrice: nil, completionPrice: nil, maxContextTokens: 200000, temperature: 0.7, topP: 1.0, maxTokens: 4096)
            ],
            routingStrategy: .localFirst,
            inference: VaultInferenceConfig(pauseOnUserInteraction: true),
            browser: BrowserConfig(allowedDomains: ["github.com", "google.com", "apple.com"]),
            mcpServers: []
        )
    }
    
    /// Returns true if at least one cloud provider is properly configured with an API key identifier.
    public nonisolated func hasCloudProvider() -> Bool {
        return config.providers.contains { provider in
            provider.type == .cloud && provider.keychainKey != nil
        }
    }
    
    public nonisolated func hasLocalConfiguration() -> Bool {
        return config.providers.contains { $0.type == .local }
    }
    
        // Ensures that 'mlx' and 'openrouter' are present. Restores defaults if missing.
    private static func syncRequiredProviders(config: inout VaultConfig, configURL: URL) throws -> Bool {
        let requiredIds = ["mlx", "openrouter"]
        let defaults: [String: ProviderConfig] = [
            "mlx": ProviderConfig(id: "mlx", type: .local, endpoint: nil, keychainKey: nil, modelName: "", capabilities: ["reasoning", "tools", "code"], costPer1KTokens: 0, promptPrice: 0, completionPrice: 0, maxContextTokens: 32768, temperature: 0.7, topP: 1.0, maxTokens: 4096),
            "openrouter": ProviderConfig(id: "openrouter", type: .cloud, endpoint: "https://openrouter.ai/api/v1", keychainKey: "OPENROUTER_API_KEY", modelName: "", capabilities: ["vision", "tools"], costPer1KTokens: nil, promptPrice: nil, completionPrice: nil, maxContextTokens: 200000, temperature: 0.7, topP: 1.0, maxTokens: 4096)
        ]
        
        var missingAny = false
        var updatedProviders = config.providers
        
        for id in requiredIds {
            if !updatedProviders.contains(where: { $0.id == id }) {
                if let defaultProv = defaults[id] {
                    updatedProviders.append(defaultProv)
                    missingAny = true
                    AgentLogger.logAudit(level: .warn, agent: "VaultManager", message: "Detected missing required provider '\(id)'. Restoring defaults...")
                }
            }
        }
        
        if missingAny {
            config = VaultConfig(
                providers: updatedProviders,
                routingStrategy: config.routingStrategy,
                inference: config.inference,
                browser: config.browser,
                mcpServers: config.mcpServers
            )
            let encoder = PropertyListEncoder()
            encoder.outputFormat = .xml
            let updatedData = try encoder.encode(config)
            try updatedData.write(to: configURL)
            return true
        }
        
        // v7.5.0: Auto-correct invalid cloud model IDs to the latest stable OpenRouter ID
        let invalidModelPatterns = ["gemini-3", "gemini-2.0-flash-lite-preview", "google/gemini-2.0-flash-lite"] // Correcting former bad fixes
        var correctedAny = false
        var finalProviders = config.providers
        for i in 0..<finalProviders.count {
            let p = finalProviders[i]
            let isInvalid = invalidModelPatterns.contains { pattern in 
                (p.modelName?.contains(pattern) ?? false) && p.modelName != "google/gemini-2.0-flash-lite-001" 
            }
            if p.id == "openrouter", isInvalid {
                AgentLogger.logAudit(level: .info, agent: "VaultManager", message: "v7.5.0: Correcting invalid model '\(p.modelName ?? "")' → google/gemini-2.0-flash-lite-001")
                finalProviders[i] = ProviderConfig(
                    id: p.id, type: p.type, endpoint: p.endpoint, keychainKey: p.keychainKey,
                    modelName: "google/gemini-2.0-flash-lite-001",
                    capabilities: p.capabilities, costPer1KTokens: p.costPer1KTokens,
                    promptPrice: p.promptPrice, completionPrice: p.completionPrice,
                    maxContextTokens: p.maxContextTokens, temperature: p.temperature,
                    topP: p.topP, maxTokens: p.maxTokens
                )
                correctedAny = true
            }
        }
        if correctedAny {
            config = VaultConfig(providers: finalProviders, routingStrategy: config.routingStrategy, inference: config.inference, browser: config.browser, mcpServers: config.mcpServers)
            let encoder = PropertyListEncoder()
            encoder.outputFormat = .xml
            let data = try encoder.encode(config)
            try data.write(to: configURL)
            return true
        }
        
        return false
    }
    
    private static func autoPrimeModelIfEmpty(config: inout VaultConfig, configURL: URL) throws -> Bool {
        var updatedProviders = config.providers
        guard let mlxIndex = updatedProviders.firstIndex(where: { $0.id == "mlx" }) else { return false }
        
        let currentModel = updatedProviders[mlxIndex].modelName ?? ""
        if !currentModel.isEmpty { return false } // Already primed
        
        guard let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else { return false }
        let modelsDir = appSupport.appendingPathComponent("EliteAgent/Models")
        
        guard let contents = try? FileManager.default.contentsOfDirectory(at: modelsDir, includingPropertiesForKeys: nil) else { return false }
        
        for url in contents where url.hasDirectoryPath {
            let modelID = url.lastPathComponent
            
            // Check if model is complete enough to bind
            let safetensorsPath = url.appendingPathComponent("model.safetensors").path
            if FileManager.default.fileExists(atPath: safetensorsPath) || FileManager.default.fileExists(atPath: url.appendingPathComponent("weights.npz").path) {
                AgentLogger.logAudit(level: .info, agent: "VaultManager", message: "🤖 AUTO-PRIMING: Discovered local model '\(modelID)'. Binding to config...")
                
                let p = updatedProviders[mlxIndex]
                updatedProviders[mlxIndex] = ProviderConfig(id: p.id, type: p.type, endpoint: p.endpoint, keychainKey: p.keychainKey, modelName: modelID, capabilities: p.capabilities, costPer1KTokens: p.costPer1KTokens, promptPrice: p.promptPrice, completionPrice: p.completionPrice, maxContextTokens: p.maxContextTokens, temperature: p.temperature, topP: p.topP, maxTokens: p.maxTokens)
                
                config = VaultConfig(providers: updatedProviders, routingStrategy: config.routingStrategy, inference: config.inference, browser: config.browser, mcpServers: config.mcpServers)
                
                let encoder = PropertyListEncoder()
                encoder.outputFormat = .xml
                let data = try encoder.encode(config)
                try data.write(to: configURL)
                return true
            }
        }
        
        return false
    }
    
    public func getAPIKey(for provider: ProviderConfig) throws -> String {
        guard let keychainKey = provider.keychainKey else {
            throw VaultError.missingKeychainResource(keychainKey: "N/A (no key specifier)")
        }
        
        do {
            let keyData = try keychain.read(key: keychainKey)
            guard let keyString = String(data: keyData, encoding: .utf8) else {
                throw KeychainError.invalidItemFormat
            }
            return keyString
        } catch KeychainError.itemNotFound {
            throw VaultError.missingKeychainResource(keychainKey: keychainKey)
        } catch let error as KeychainError {
            throw VaultError.apiTokenReadFailed(error.description)
        } catch {
            throw VaultError.apiTokenReadFailed(error.localizedDescription)
        }
    }
    
    public func readSecret(for key: String) throws -> String {
        do {
            let keyData = try keychain.read(key: key)
            guard let keyString = String(data: keyData, encoding: .utf8) else {
                throw KeychainError.invalidItemFormat
            }
            return keyString
        } catch {
            throw VaultError.missingKeychainResource(keychainKey: key)
        }
    }
    
    public func updateModelPricing(for providerID: String, modelName: String, promptPrice: Decimal? = nil, completionPrice: Decimal? = nil, temperature: Double? = nil, topP: Double? = nil, maxTokens: Int? = nil) throws {
        let data = try Data(contentsOf: configURL)
        var format = PropertyListSerialization.PropertyListFormat.xml
        let obj = try PropertyListSerialization.propertyList(from: data, options: .init(), format: &format)
        
        guard var existingPlist = obj as? [String: Any],
              var providers = existingPlist["providers"] as? [[String: Any]] else { return }
        
        for i in 0..<providers.count {
            if providers[i]["id"] as? String == providerID {
                var updatedProvider = providers[i]
                updatedProvider["modelName"] = modelName
                if let p = promptPrice { updatedProvider["promptPrice"] = Double(truncating: p as NSNumber) }
                if let c = completionPrice { updatedProvider["completionPrice"] = Double(truncating: c as NSNumber) }
                if let t = temperature { updatedProvider["temperature"] = t }
                if let tp = topP { updatedProvider["topP"] = tp }
                if let mt = maxTokens { updatedProvider["maxTokens"] = mt }
                providers[i] = updatedProvider
            }
        }
        
        existingPlist["providers"] = providers
        
        let updatedData = try PropertyListSerialization.data(fromPropertyList: existingPlist as Any, format: format, options: .init())
        try updatedData.write(to: configURL, options: .init())
        
        AgentLogger.logInfo("Updated model/pricing/params for \(providerID): \(modelName)", agent: "VaultManager")
    }
    
    // Helper to add a whole new provider
    public func addProvider(_ provider: ProviderConfig) throws {
        let data = try Data(contentsOf: configURL)
        var format = PropertyListSerialization.PropertyListFormat.xml
        let obj = try PropertyListSerialization.propertyList(from: data, options: .init(), format: &format)
        
        guard var existingPlist = obj as? [String: Any],
              var providers = existingPlist["providers"] as? [[String: Any]] else { return }
        
        let encoder = PropertyListEncoder()
        let providerData = try encoder.encode(provider)
        let providerDict = try PropertyListSerialization.propertyList(from: providerData, options: .init(), format: nil) as? [String: Any] ?? [:]
        
        providers.append(providerDict)
        existingPlist["providers"] = providers
        
        let updatedData = try PropertyListSerialization.data(fromPropertyList: existingPlist as Any, format: format, options: .init())
        try updatedData.write(to: configURL, options: .init())
    }
    
    /// Securely saves a secret to the Keychain.
    public func saveSecret(key: String, value: String) throws {
        guard let data = value.data(using: .utf8) else {
            throw KeychainError.invalidItemFormat
        }
        try keychain.save(key: key, data: data)
    }
    
    /// Links a provider's keychain identifier to a new token value.
    public func updateAPIKey(for providerID: String, token: String) throws {
        guard let provider = config.providers.first(where: { $0.id == providerID }),
              let keychainKey = provider.keychainKey else {
            throw VaultError.missingKeychainResource(keychainKey: "Provider \(providerID) has no keychain key")
        }
        try saveSecret(key: keychainKey, value: token)
    }
}
