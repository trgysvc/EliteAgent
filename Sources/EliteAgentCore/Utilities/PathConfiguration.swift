// PathConfiguration.swift
// EliteAgent Core — Apple Standards Component

import Foundation

public struct PathConfiguration: Sendable {
    public static let shared = PathConfiguration()
    
    private let bundleName = "EliteAgent"
    
    private init() {}
    
    /// ~/Library/Application Support/EliteAgent
    public var applicationSupportURL: URL {
        let root = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first ?? URL(fileURLWithPath: "/tmp")
        let url = root.appendingPathComponent(bundleName, isDirectory: true)
        ensureDirectoryExists(at: url)
        return url
    }
    
    /// ~/Library/Caches/EliteAgent
    public var cachesURL: URL {
        let root = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first ?? URL(fileURLWithPath: "/tmp")
        let url = root.appendingPathComponent(bundleName, isDirectory: true)
        ensureDirectoryExists(at: url)
        return url
    }
    
    /// ~/Library/Logs/EliteAgent
    public var logsURL: URL {
        let root = FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask).first ?? URL(fileURLWithPath: "/tmp")
        let url = root.appendingPathComponent("Logs", isDirectory: true)
            .appendingPathComponent(bundleName, isDirectory: true)
        ensureDirectoryExists(at: url)
        return url
    }
    
    /// ~/Library/Application Support/EliteAgent/Models (v14.0: Persist models during cache sweeps)
    public var modelsURL: URL {
        let url = applicationSupportURL.appendingPathComponent("Models", isDirectory: true)
        ensureDirectoryExists(at: url)
        return url
    }
    
    /// ~/Library/Application Support/EliteAgent/Trajectories (v27.0: Structured session analysis)
    public var trajectoriesURL: URL {
        let url = applicationSupportURL.appendingPathComponent("Trajectories", isDirectory: true)
        ensureDirectoryExists(at: url)
        return url
    }
    
    /// ~/Workspaces/EliteAgent (v27.0: User workspace, excluded from factory resets)
    public var workspaceURL: URL {
        let home = URL(fileURLWithPath: NSHomeDirectory())
        let url = home.appendingPathComponent("Workspaces", isDirectory: true)
                      .appendingPathComponent("EliteAgent", isDirectory: true)
        ensureDirectoryExists(at: url)
        return url
    }
    
    // MARK: - Specific Files
    
    public var vaultURL: URL {
        return applicationSupportURL.appendingPathComponent("vault.plist")
    }
    
    public var historyURL: URL {
        return applicationSupportURL.appendingPathComponent("history.plist")
    }
    
    public var memoryDBURL: URL {
        return applicationSupportURL.appendingPathComponent("memory.db")
    }
    
    public var auditLogURL: URL {
        return logsURL.appendingPathComponent("audit.log")
    }
    
    // MARK: - Helpers
    
    private func ensureDirectoryExists(at url: URL) {
        if !FileManager.default.fileExists(atPath: url.path) {
            try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true, attributes: nil)
        }
    }
}
