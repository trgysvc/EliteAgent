import Foundation

public struct WriteFileTool: AgentTool, Sendable {
    public let name = "write_file"
    public let summary = "Create or overwrite worker files using Native swift APIs."
    public let description = "Write or overwrite a file in the workspace or allowed home directories. MANDATORY: Use this instead of 'echo >' or shell redirection for all file writing tasks."
    public let ubid = 34 // Token 'C' in Qwen 2.5
    
    public init() {}
    
    public func execute(params: [String: AnyCodable], session: Session) async throws -> String {
        let rawPath = params["path"]?.value as? String ?? ""
        let content = params["content"]?.value as? String ?? ""
        
        let expandedPath = rawPath.hasPrefix("~") 
            ? rawPath.replacingOccurrences(of: "~", with: FileManager.default.homeDirectoryForCurrentUser.path) 
            : rawPath
        
        let fileURL: URL
        if expandedPath.hasPrefix("/") {
            fileURL = URL(fileURLWithPath: expandedPath).standardizedFileURL
        } else {
            fileURL = session.workspaceURL.appendingPathComponent(expandedPath).standardizedFileURL
        }
        
        // Security check: Allow writes in Workspace OR User's Home (Documents, etc.)
        let homeURL = FileManager.default.homeDirectoryForCurrentUser.standardizedFileURL
        let workspaceURL = session.workspaceURL.standardizedFileURL
        
        guard fileURL.path.hasPrefix(workspaceURL.path) || fileURL.path.hasPrefix(homeURL.path) else {
            throw NSError(domain: "WriteFileTool", code: 2, userInfo: [NSLocalizedDescriptionKey: "Path is outside allowed boundaries (Home or Workspace)"])
        }
        
        let parentURL = fileURL.deletingLastPathComponent()
        if !FileManager.default.fileExists(atPath: parentURL.path) {
            try FileManager.default.createDirectory(at: parentURL, withIntermediateDirectories: true, attributes: nil)
        }
        
        try content.write(to: fileURL, atomically: true, encoding: .utf8)
        return "File written: \(rawPath)"
    }
}
