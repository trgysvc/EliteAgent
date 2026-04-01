import Foundation
import PDFKit

public struct ReadFileTool: AgentTool, Sendable {
    public let name = "read_file"
    public let description = "Read content from a file (.txt, .pdf, .docx)."
    
    public init() {}
    
    public func execute(params: [String: AnyCodable], session: Session) async throws -> String {
        let rawPath = params["path"]?.value as? String ?? ""
        let expandedPath = rawPath.hasPrefix("~") 
            ? rawPath.replacingOccurrences(of: "~", with: FileManager.default.homeDirectoryForCurrentUser.path) 
            : rawPath
        
        let fileURL: URL
        if expandedPath.hasPrefix("/") {
            fileURL = URL(fileURLWithPath: expandedPath).standardizedFileURL
        } else {
            fileURL = session.workspaceURL.appendingPathComponent(expandedPath).standardizedFileURL
        }
        
        // Security check: Allow reads in Workspace OR User's Home
        let homeURL = FileManager.default.homeDirectoryForCurrentUser.standardizedFileURL
        let workspaceURL = session.workspaceURL.standardizedFileURL
        
        guard fileURL.path.hasPrefix(workspaceURL.path) || fileURL.path.hasPrefix(homeURL.path) else {
            throw NSError(domain: "ReadFileTool", code: 2, userInfo: [NSLocalizedDescriptionKey: "Path is outside allowed boundaries (Home or Workspace)"])
        }
        
        let ext = fileURL.pathExtension.lowercased()
        
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            throw ToolError.executionError("File not found: \(rawPath)")
        }
        
        switch ext {
        case "pdf":
            guard let pdf = PDFDocument(url: fileURL) else {
                throw ToolError.executionError("Failed to load PDF document at \(rawPath)")
            }
            return pdf.string ?? ""
            
        case "docx":
            // Use system textutil to extract text from docx
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/textutil")
            process.arguments = ["-convert", "txt", "-stdout", fileURL.path]
            
            let pipe = Pipe()
            process.standardOutput = pipe
            
            try process.run()
            process.waitUntilExit()
            
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            return String(data: data, encoding: .utf8) ?? ""
            
        default:
            // Standard text files
            return try String(contentsOf: fileURL, encoding: .utf8)
        }
    }
}
