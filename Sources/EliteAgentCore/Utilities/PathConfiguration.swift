// PathConfiguration.swift
// EliteAgent Core — Apple Standards Component

import Foundation

public struct PathConfiguration: Sendable {
    public static let shared = PathConfiguration()
    
    private let bundleName = "EliteAgent"
    
    private init() {}
    
    /// ~/Library/Application Support/EliteAgent
    public var applicationSupportURL: URL {
        let url = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            .appendingPathComponent(bundleName, isDirectory: true)
        ensureDirectoryExists(at: url)
        return url
    }
    
    /// ~/Library/Caches/EliteAgent
    public var cachesURL: URL {
        let url = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first!
            .appendingPathComponent(bundleName, isDirectory: true)
        ensureDirectoryExists(at: url)
        return url
    }
    
    /// ~/Library/Logs/EliteAgent
    public var logsURL: URL {
        let url = FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask).first!
            .appendingPathComponent("Logs", isDirectory: false)
            .appendingPathComponent(bundleName, isDirectory: true)
        ensureDirectoryExists(at: url)
        return url
    }
    
    // MARK: - Specific Files
    
    public var vaultURL: URL {
        return applicationSupportURL.appendingPathComponent("vault.plist")
    }
    
    public var historyURL: URL {
        return applicationSupportURL.appendingPathComponent("history.json")
    }
    
    public var memoryDBURL: URL {
        return applicationSupportURL.appendingPathComponent("memory.db")
    }
    
    public var auditLogURL: URL {
        return logsURL.appendingPathComponent("audit.log")
    }
    
    // MARK: - Migration Helper
    
    public var legacyBaseURL: URL {
        return URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent(".eliteagent")
    }
    
    public func performMigration() {
        let legacy = legacyBaseURL
        let target = applicationSupportURL
        
        guard FileManager.default.fileExists(atPath: legacy.path) else { return }
        print("[MIGRATION] Detected legacy .eliteagent folder. Moving to standard Application Support...")
        
        let filesToMove = ["vault.plist", "history.json", "memory.db", "task_history.jsonl"]
        
        for file in filesToMove {
            let oldURL = legacy.appendingPathComponent(file)
            let newURL = target.appendingPathComponent(file)
            
            if FileManager.default.fileExists(atPath: oldURL.path) && !FileManager.default.fileExists(atPath: newURL.path) {
                try? FileManager.default.moveItem(at: oldURL, to: newURL)
                print("[MIGRATION] Moved \(file) to standard path.")
            }
        }
        
        // Remove legacy folder if empty or rename to avoid re-migration
        if (try? FileManager.default.contentsOfDirectory(atPath: legacy.path).isEmpty) == true {
             try? FileManager.default.removeItem(at: legacy)
        } else {
             try? FileManager.default.moveItem(at: legacy, to: URL(fileURLWithPath: legacy.path + "_legacy_bak"))
        }
    }
    
    // MARK: - Helpers
    
    private func ensureDirectoryExists(at url: URL) {
        if !FileManager.default.fileExists(atPath: url.path) {
            try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true, attributes: nil)
        }
    }
}
