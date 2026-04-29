import Foundation
import PDFKit

public struct ReadFileTool: AgentTool, Sendable {
    public let name = "read_file"
    public let summary = "Read content from .txt, .pdf, .docx files."
    public let description = "Read content from a file (.txt, .pdf, .docx)."
    public let ubid: Int128 = 33 // Token 'B' in Qwen 2.5
    
    public init() {}
    
    public func execute(params: [String: AnyCodable], session: Session) async throws(AgentToolError) -> String {
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
        
        // Security check: Allow reads in Workspace OR User's Home (robust validation)
        let homePath = FileManager.default.homeDirectoryForCurrentUser.standardizedFileURL.path
        let workspacePath = session.workspaceURL.standardizedFileURL.path
        let standardizedPath = fileURL.standardizedFileURL.path
        
        let isIsolationEnabled = await AppSettings.shared.isWorkspaceIsolationEnabled
        
        if isIsolationEnabled {
            guard standardizedPath.hasPrefix(workspacePath) else {
                AgentLogger.logAudit(level: .warn, agent: "ReadFileTool", message: "Access Denied (Isolation): \(standardizedPath)")
                throw AgentToolError.executionError("GÜVENLİK ENGELİ: Çalışma Alanı İzolasyonu AÇIK. Sadece '\(workspacePath)' altındaki dosyaları okuyabilirsiniz. (İzolasyonu Ayarlar'dan kapatabilirsiniz)")
            }
        } else {
            let isAllowed = standardizedPath.hasPrefix(workspacePath) || standardizedPath.hasPrefix(homePath)
            guard isAllowed else {
                AgentLogger.logAudit(level: .warn, agent: "ReadFileTool", message: "Access Denied: \(standardizedPath). Allowed Prefixes: [\(workspacePath), \(homePath)]")
                throw AgentToolError.executionError("Path is outside allowed boundaries (Home or Workspace)")
            }
        }
        
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            throw AgentToolError.executionError("File not found: \(rawPath)")
        }
        
        let ext = fileURL.pathExtension.lowercased()
        let audioExtensions = ["mp3", "m4a", "wav", "flac", "aac"]
        if audioExtensions.contains(ext) {
            return "AUDIO_FILE_DETECTED: This is a binary audio file. You CANNOT read its content as text. USE 'music_dna' tool with path: '\(fileURL.path)' for technical analysis."
        }
        
        do {
            switch ext {
            case "pdf":
                guard let pdf = PDFDocument(url: fileURL) else {
                    throw AgentToolError.executionError("Failed to load PDF document at \(rawPath)")
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
        } catch {
            if let toolError = error as? AgentToolError {
                throw toolError
            }
            throw AgentToolError.executionError(error.localizedDescription)
        }
    }
}
