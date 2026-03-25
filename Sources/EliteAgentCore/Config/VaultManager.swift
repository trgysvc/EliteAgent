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
    public let maxContextTokens: Int?
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
        guard FileManager.default.fileExists(atPath: configURL.path) else {
            throw VaultError.fileNotFound(configURL)
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
    
    public func updateModelName(for providerID: String, to newModelName: String) throws {
        let data = try Data(contentsOf: configURL)
        var format = PropertyListSerialization.PropertyListFormat.xml
        let obj = try PropertyListSerialization.propertyList(from: data, options: .init(), format: &format)
        let plist = obj as? [String: Any]
        
        guard let existingPlist = plist,
              var providers = existingPlist["providers"] as? [[String: Any]] else { return }
        
        for i in 0..<providers.count {
            if providers[i]["id"] as? String == providerID {
                var updatedProvider = providers[i]
                updatedProvider["modelName"] = newModelName
                providers[i] = updatedProvider
            }
        }
        
        var updatedPlist = existingPlist
        updatedPlist["providers"] = providers
        
        let updatedData = try PropertyListSerialization.data(fromPropertyList: updatedPlist as Any, format: format, options: .init())
        try updatedData.write(to: configURL, options: .init())
        
        print("[VaultManager] Updated modelName to \(newModelName) for provider \(providerID)")
    }
}
