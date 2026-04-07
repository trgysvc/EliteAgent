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
            .appendingPathComponent("Logs", isDirectory: true)
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
        
        // v7.5.1: Only proceed if the legacy folder exists AND hasn't been marked as migrated
        guard FileManager.default.fileExists(atPath: legacy.path) else { return }
        
        let filesToMove = ["vault.plist", "history.json", "memory.db", "task_history.jsonl"]
        let hasActualFiles = filesToMove.contains { file in
            FileManager.default.fileExists(atPath: legacy.appendingPathComponent(file).path)
        }
        
        guard hasActualFiles else {
            // No actual files left to move, just get rid of the folder (or rename it)
            cleanupLegacyFolder(legacy: legacy)
            return
        }

        print("[MIGRATION] Detected legacy .eliteagent folder with data. Moving to standard Application Support...")
        
        for file in filesToMove {
            let oldURL = legacy.appendingPathComponent(file)
            let newURL = target.appendingPathComponent(file)
            
            if FileManager.default.fileExists(atPath: oldURL.path) && !FileManager.default.fileExists(atPath: newURL.path) {
                try? FileManager.default.moveItem(at: oldURL, to: newURL)
                print("[MIGRATION] Moved \(file) to standard path.")
            }
        }
        
        // Final Cleanup
        cleanupLegacyFolder(legacy: legacy)
    }
    
    private func cleanupLegacyFolder(legacy: URL) {
        let items = (try? FileManager.default.contentsOfDirectory(atPath: legacy.path)) ?? []
        if items.isEmpty {
            try? FileManager.default.removeItem(at: legacy)
        } else {
            // Rename to avoid re-triggering migration logic
            let renamed = legacy.deletingLastPathComponent().appendingPathComponent(".eliteagent_migrated_bak")
            if !FileManager.default.fileExists(atPath: renamed.path) {
                try? FileManager.default.moveItem(at: legacy, to: renamed)
            } else {
                // If bak already exists, just try to delete the contents or items
                try? FileManager.default.removeItem(at: legacy)
            }
        }
    }
    
    // MARK: - Helpers
    
    private func ensureDirectoryExists(at url: URL) {
        if !FileManager.default.fileExists(atPath: url.path) {
            try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true, attributes: nil)
        }
    }
}
