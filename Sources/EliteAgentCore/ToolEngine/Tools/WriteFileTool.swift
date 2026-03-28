import Foundation

public struct WriteFileTool: AgentTool, Sendable {
    public let name = "write_file"
    public let description = "Write or overwrite a file in the workspace."
    
    public init() {}
    
    public func execute(params: [String: AnyCodable], session: Session) async throws -> String {
        guard let path = params["path"]?.value as? String,
              let content = params["content"]?.value as? String else {
            throw NSError(domain: "WriteFileTool", code: 1, userInfo: [NSLocalizedDescriptionKey: "Missing 'path' or 'content' parameters"])
        }
        
        let workspaceURL = session.workspaceURL
        let fileURL = workspaceURL.appendingPathComponent(path).standardizedFileURL
        
        // Security check: Ensure file is inside workspace
        guard fileURL.path.hasPrefix(workspaceURL.path) else {
            throw NSError(domain: "WriteFileTool", code: 2, userInfo: [NSLocalizedDescriptionKey: "Path is outside workspace boundaries"])
        }
        
        let parentURL = fileURL.deletingLastPathComponent()
        if !FileManager.default.fileExists(atPath: parentURL.path) {
            try FileManager.default.createDirectory(at: parentURL, withIntermediateDirectories: true, attributes: nil)
        }
        
        try content.write(to: fileURL, atomically: true, encoding: .utf8)
        return "File written: \(path)"
    }
}
