import Foundation
import PDFKit

public struct ReadFileTool: AgentTool, Sendable {
    public let name = "read_file"
    public let description = "Read content from a file (.txt, .pdf, .docx)."
    
    public init() {}
    
    public func execute(params: [String: AnyCodable], session: Session) async throws -> String {
        guard let path = params["path"]?.value as? String else {
            throw ToolError.missingParameter("Missing 'path' parameter")
        }
        
        let fileURL = session.workspaceURL.appendingPathComponent(path).standardizedFileURL
        let ext = fileURL.pathExtension.lowercased()
        
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            throw ToolError.executionError("File not found: \(path)")
        }
        
        switch ext {
        case "pdf":
            guard let pdf = PDFDocument(url: fileURL) else {
                throw ToolError.executionError("Failed to load PDF document at \(path)")
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
