import Foundation

public struct BrowserConfig: Codable, Sendable {
    public let allowedDomains: [String]
}

public struct VaultConfig: Codable, Sendable {
    public let providers: [ProviderConfig]
    public let routingStrategy: RoutingStrategy
    public let inference: InferenceConfig?
    public let browser: BrowserConfig?
}

public struct ProviderConfig: Codable, Sendable {
    public let id: String
    public let type: ProviderType
    public let endpoint: String?
    public let keychainKey: String?
    public let modelName: String?
    public let capabilities: [String]?
    public let costPer1KTokens: Decimal?
    public let promptPrice: Decimal?
    public let completionPrice: Decimal?
    public let maxContextTokens: Int?
    public let temperature: Double?
    public let topP: Double?
    public let maxTokens: Int?
    
    public init(id: String, type: ProviderType, endpoint: String?, keychainKey: String?, modelName: String?, capabilities: [String]?, costPer1KTokens: Decimal?, promptPrice: Decimal?, completionPrice: Decimal?, maxContextTokens: Int?, temperature: Double?, topP: Double?, maxTokens: Int?) {
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

public struct InferenceConfig: Codable, Sendable {
    public let pauseOnUserInteraction: Bool?
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
    public let config: VaultConfig
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
            print("[VaultManager] Config missing at \(configURL.path). Creating default...")
            let defaultConfig = VaultConfig(
                providers: [
                    ProviderConfig(id: "mlx", type: .local, endpoint: nil, keychainKey: nil, modelName: "deepseek-r1-8b", capabilities: ["reasoning", "tools"], costPer1KTokens: 0, promptPrice: 0, completionPrice: 0, maxContextTokens: 32768, temperature: 0.7, topP: 1.0, maxTokens: 4096),
                    ProviderConfig(id: "openrouter", type: .cloud, endpoint: "https://openrouter.ai/api/v1", keychainKey: "OPENROUTER_API_KEY", modelName: "google/gemini-3.1-flash-lite-preview", capabilities: ["vision", "tools"], costPer1KTokens: nil, promptPrice: nil, completionPrice: nil, maxContextTokens: 200000, temperature: 0.7, topP: 1.0, maxTokens: 4096)
                ],
                routingStrategy: .localFirst,
                inference: InferenceConfig(pauseOnUserInteraction: true),
                browser: BrowserConfig(allowedDomains: ["github.com", "google.com", "apple.com"])
            )
            let encoder = PropertyListEncoder()
            encoder.outputFormat = .xml
            let defaultData = try encoder.encode(defaultConfig)
            try defaultData.write(to: configURL)
        }
        
        do {
            let data = try Data(contentsOf: configURL)
            let decoder = PropertyListDecoder()
            self.config = try decoder.decode(VaultConfig.self, from: data)
        } catch {
            throw VaultError.invalidFormat(error)
        }
    }
    
    public func getAPIKey(for provider: ProviderConfig) throws -> String {
        guard let keychainKey = provider.keychainKey else {
            throw VaultError.missingKeychainResource(keychainKey: "N/A (no key specifier)")
        }
        
        do {
            print("[TRACE] VaultManager: Attempting to read '\(keychainKey)' from Keychain...")
            let keyData = try keychain.read(key: keychainKey)
            guard let keyString = String(data: keyData, encoding: .utf8) else {
                throw KeychainError.invalidItemFormat
            }
            print("[TRACE] VaultManager: Successfully retrieved API Key for '\(keychainKey)'.")
            return keyString
        } catch KeychainError.itemNotFound {
            print("[TRACE] VaultManager: API Key NOT FOUND for identifier '\(keychainKey)'.")
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
                if let p = promptPrice { updatedProvider["promptPrice"] = p }
                if let c = completionPrice { updatedProvider["completionPrice"] = c }
                if let t = temperature { updatedProvider["temperature"] = t }
                if let tp = topP { updatedProvider["topP"] = tp }
                if let mt = maxTokens { updatedProvider["maxTokens"] = mt }
                providers[i] = updatedProvider
            }
        }
        
        existingPlist["providers"] = providers
        
        let updatedData = try PropertyListSerialization.data(fromPropertyList: existingPlist as Any, format: format, options: .init())
        try updatedData.write(to: configURL, options: .init())
        
        print("[VaultManager] Updated model/pricing/params for \(providerID): \(modelName)")
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
}
