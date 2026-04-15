import Foundation
import CryptoKit
import OSLog

/// A secure actor for managing encrypted audit logs.
/// Complies with EliteAgent v10.0 security standards.
public actor AuditLoggerActor {
    public static let shared = AuditLoggerActor()
    
    private let logger = Logger(subsystem: "com.elite.agent", category: "AuditLogger")
    private let keychainTag = "com.elite.agent.audit.key"
    
    private init() {}
    
    /// Records a log entry with optional encryption.
    public func logExecution(tool: String, params: [String: Any], approved: Bool, mode: String) async {
        let entry: [String: Any] = [
            "timestamp": ISO8601DateFormatter().string(from: Date()),
            "tool": tool,
            "params": params,
            "approved": approved,
            "mode": mode
        ]
        
        do {
            // v13.8: UNO Pure - Binary PropertyList Serialization (No JSON Artıkları)
            let data = try PropertyListSerialization.data(fromPropertyList: entry, format: .binary, options: 0)
            
            // Check if encryption is enabled in settings
            let shouldEncrypt = UserDefaults.standard.bool(forKey: "Settings_encryptAuditLogs")
            
            if shouldEncrypt {
                let encryptedData = try encrypt(data)
                try save(data: encryptedData, isEncrypted: true)
            } else {
                try save(data: data, isEncrypted: false)
            }
            
            logger.info("AUDIT: Recorded \(tool) execution (Mode: \(mode))")
        } catch {
            logger.error("AUDIT FAILED: \(error.localizedDescription)")
        }
    }
    
    // MARK: - Private Crypto
    
    private func encrypt(_ data: Data) throws -> Data {
        let key = try getOrCreateKey()
        let sealedBox = try AES.GCM.seal(data, using: key)
        return sealedBox.combined!
    }
    
    private func getOrCreateKey() throws -> SymmetricKey {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: keychainTag,
            kSecReturnData as String: true
        ]
        
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        
        if status == errSecSuccess, let data = result as? Data {
            return SymmetricKey(data: data)
        } else {
            // Create new key
            let key = SymmetricKey(size: .bits256)
            let keyData = key.withUnsafeBytes { Data($0) }
            
            let addQuery: [String: Any] = [
                kSecClass as String: kSecClassGenericPassword,
                kSecAttrAccount as String: keychainTag,
                kSecValueData as String: keyData
            ]
            SecItemAdd(addQuery as CFDictionary, nil)
            return key
        }
    }
    
    private func save(data: Data, isEncrypted: Bool) throws {
        let logFileName = isEncrypted ? "audit_log.enc" : "audit_log.plist"
        let logURL = PathConfiguration.shared.logsURL.appendingPathComponent(logFileName)
        
        if !FileManager.default.fileExists(atPath: logURL.path) {
            FileManager.default.createFile(atPath: logURL.path, contents: nil, attributes: nil)
        }
        
        let fileHandle = try FileHandle(forWritingTo: logURL)
        defer { try? fileHandle.close() }
        try fileHandle.seekToEnd()
        try fileHandle.write(contentsOf: data)
    }
}
