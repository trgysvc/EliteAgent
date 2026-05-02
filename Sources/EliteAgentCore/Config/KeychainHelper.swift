import Foundation
import Security

public enum KeychainError: Error, CustomStringConvertible, Sendable {
    case duplicateEntry
    case unknown(OSStatus)
    case itemNotFound
    case invalidItemFormat
    case accessDenied // PRD Madde 22.6
    
    public var description: String {
        switch self {
        case .duplicateEntry: return "Keychain item already exists."
        case .unknown(let status): return "Unknown Keychain error: \(status)"
        case .itemNotFound: return "Keychain item not found."
        case .invalidItemFormat: return "Invalid item format in Keychain."
        case .accessDenied: return "Keychain Access Denied. Check permissions."
        }
    }
}

public struct KeychainHelper: Sendable {
    private let serviceIdentifier = "com.trgysvc.EliteAgent"
    private let legacyServiceIdentifier = "com.eliteagent"
    
    public init() {}
    
    public func save(key: String, data: Data) throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceIdentifier,
            kSecAttrAccount as String: key,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlocked
        ]
        
        let status = SecItemAdd(query as CFDictionary, nil)
        
        guard status == errSecSuccess else {
            if status == errSecDuplicateItem {
                let updateQuery: [String: Any] = [
                    kSecClass as String: kSecClassGenericPassword,
                    kSecAttrService as String: serviceIdentifier,
                    kSecAttrAccount as String: key
                ]
                let attributes: [String: Any] = [
                    kSecValueData as String: data
                ]
                let updateStatus = SecItemUpdate(updateQuery as CFDictionary, attributes as CFDictionary)
                guard updateStatus == errSecSuccess else {
                    if updateStatus == errSecAuthFailed { throw KeychainError.accessDenied }
                    throw KeychainError.unknown(updateStatus)
                }
            } else if status == errSecAuthFailed {
                throw KeychainError.accessDenied
            } else {
                throw KeychainError.unknown(status)
            }
            return
        }
    }
    
    public func read(key: String) throws -> Data {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceIdentifier,
            kSecAttrAccount as String: key,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        
        var dataTypeRef: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &dataTypeRef)
        
        guard status == errSecSuccess else {
            if status == errSecItemNotFound {
                // FALLBACK: Try legacy identifier
                let legacyQuery: [String: Any] = [
                    kSecClass as String: kSecClassGenericPassword,
                    kSecAttrService as String: legacyServiceIdentifier,
                    kSecAttrAccount as String: key,
                    kSecReturnData as String: true,
                    kSecMatchLimit as String: kSecMatchLimitOne
                ]
                var legacyRef: AnyObject?
                let legacyStatus = SecItemCopyMatching(legacyQuery as CFDictionary, &legacyRef)
                
                if legacyStatus == errSecSuccess, let legacyData = legacyRef as? Data {
                    AgentLogger.logAudit(level: .info, agent: "Keychain", message: "Found key in legacy namespace '\(legacyServiceIdentifier)'. Migrating...")
                    // Optionally migrate here, but for now just return
                    return legacyData
                }
                
                throw KeychainError.itemNotFound 
            }
            if status == errSecAuthFailed { throw KeychainError.accessDenied }
            throw KeychainError.unknown(status)
        }
        
        guard let data = dataTypeRef as? Data else {
            throw KeychainError.invalidItemFormat
        }
        return data
    }
    
    public func delete(key: String) throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceIdentifier,
            kSecAttrAccount as String: key
        ]
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            if status == errSecAuthFailed { throw KeychainError.accessDenied }
            throw KeychainError.unknown(status)
        }
    }
}
