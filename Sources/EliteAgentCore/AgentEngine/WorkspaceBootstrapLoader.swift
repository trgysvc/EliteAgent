import Foundation
import OSLog

/// v27.0: Workspace Bootstrap Loader (OpenClaw-Inspired)
/// Automatically finds and loads configuration/context files from the workspace.
/// Enables persistent project rules and context across sessions.
public struct WorkspaceBootstrapLoader {
    
    private static let logger = Logger(subsystem: "com.elite.agent", category: "Bootstrap")
    
    /// Files to look for in the workspace, in priority order.
    public static let bootstrapFiles = ["AGENTS.md", "ELITE.md", "CONTEXT.md"]
    
    /// Loads bootstrap content from the given workspace URL.
    /// - Parameter workspaceURL: The root directory of the workspace.
    /// - Returns: A combined string of all found bootstrap files.
    public static func load(workspaceURL: URL) async -> String {
        var combinedContent = ""
        
        for fileName in bootstrapFiles {
            let fileURL = workspaceURL.appendingPathComponent(fileName)
            if FileManager.default.fileExists(atPath: fileURL.path) {
                do {
                    let content = try String(contentsOf: fileURL, encoding: .utf8)
                    combinedContent += "\n### WORKSPACE BOOTSTRAP: \(fileName) ###\n\(content)\n"
                    logger.info("Loaded bootstrap file: \(fileName)")
                } catch {
                    logger.error("Failed to load bootstrap file \(fileName): \(error.localizedDescription)")
                }
            }
        }
        
        return combinedContent
    }
    
    /// Checks if any bootstrap files exist in the workspace.
    public static func hasBootstrapFiles(workspaceURL: URL) -> Bool {
        return bootstrapFiles.contains { fileName in
            FileManager.default.fileExists(atPath: workspaceURL.appendingPathComponent(fileName).path)
        }
    }
}
