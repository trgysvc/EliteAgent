import Foundation

public final class WorkspaceManager: Sendable {
    public static let shared = WorkspaceManager()
    
    private let baseTempDir: URL
    
    private init() {
        let home = FileManager.default.homeDirectoryForCurrentUser
        self.baseTempDir = home.appendingPathComponent(".eliteagent/workspaces", isDirectory: true)
        
        try? FileManager.default.createDirectory(at: baseTempDir, withIntermediateDirectories: true)
    }
    
    public func createWorkspace(for sessionID: UUID) throws -> URL {
        let workspaceURL = baseTempDir.appendingPathComponent(sessionID.uuidString, isDirectory: true)
        
        try FileManager.default.createDirectory(at: workspaceURL, withIntermediateDirectories: true)
        return workspaceURL
    }
    
    public func cleanupWorkspace(for sessionID: UUID) {
        let workspaceURL = baseTempDir.appendingPathComponent(sessionID.uuidString, isDirectory: true)
        try? FileManager.default.removeItem(at: workspaceURL)
    }
    
    public func resolveInheritedWorkspace(parentID: UUID) -> URL {
        return baseTempDir.appendingPathComponent(parentID.uuidString, isDirectory: true)
    }
}
