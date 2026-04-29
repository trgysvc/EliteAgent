import Foundation

public struct WriteFileTool: AgentTool, Sendable {
    public let name = "write_file"
    public let summary = "Create or overwrite worker files using Native swift APIs."
    public let description = "Write or overwrite a file in the workspace or allowed home directories. MANDATORY: Use this instead of 'echo >' or shell redirection. Parameters: path (string), content (string), force (bool, optional)."
    public let ubid: Int128 = 34 // Token 'C' in Qwen 2.5
    
    private let binaryExtensions = [".mp3", ".wav", ".m4a", ".png", ".jpg", ".jpeg", ".zip", ".dmg", ".pkg", ".app", ".exe", ".bin"]
    
    public init() {}
    
    public func execute(params: [String: AnyCodable], session: Session) async throws(AgentToolError) -> String {
        // v19.7.7: Smart Normalization for SLM hallucinations
        var finalPath = params["path"]?.value as? String ?? ""
        var finalContent = params["content"]?.value as? String ?? ""
        
        // Hallucination Recovery: If 'path' is missing but 'action' exists, use it.
        if finalPath.isEmpty, let altPath = params["action"]?.value as? String {
            finalPath = altPath
        }
        
        // Hallucination Recovery: If 'content' is missing but 'param' or 'text' exists, use it.
        if finalContent.isEmpty {
            if let altContent = params["param"]?.value as? String { finalContent = altContent }
            else if let altContent = params["text"]?.value as? String { finalContent = altContent }
        }
        
        let force = params["force"]?.value as? Bool ?? false

        
        guard !finalPath.isEmpty else {
            throw AgentToolError.missingParameter("path (HATA: Dosya yolu belirtilmedi. Klasörün üzerine yazamazsınız.)")
        }
        
        let expandedPath = finalPath.hasPrefix("~") 
            ? finalPath.replacingOccurrences(of: "~", with: FileManager.default.homeDirectoryForCurrentUser.path) 
            : finalPath
        
        let fileURL: URL
        if expandedPath.hasPrefix("/") {
            fileURL = URL(fileURLWithPath: expandedPath).standardizedFileURL
        } else {
            fileURL = session.workspaceURL.appendingPathComponent(expandedPath).standardizedFileURL
        }
        
        // Security check: Allow writes in Workspace OR User's Home (Documents, etc.)
        let homeURL = FileManager.default.homeDirectoryForCurrentUser.standardizedFileURL
        let workspaceURL = session.workspaceURL.standardizedFileURL
        
        let isIsolationEnabled = await AppSettings.shared.isWorkspaceIsolationEnabled
        
        if isIsolationEnabled {
            guard fileURL.path.hasPrefix(workspaceURL.path) else {
                throw AgentToolError.executionError("GÜVENLİK ENGELİ: Çalışma Alanı İzolasyonu AÇIK. Sadece '\(workspaceURL.path)' içerisine dosya yazabilirsiniz. (İzolasyonu Ayarlar'dan kapatabilirsiniz)")
            }
        } else {
            guard fileURL.path.hasPrefix(workspaceURL.path) || fileURL.path.hasPrefix(homeURL.path) else {
                throw AgentToolError.executionError("Path is outside allowed boundaries (Home or Workspace)")
            }
        }
        
        let parentURL = fileURL.deletingLastPathComponent()
        
        // v19.7.7: Robust Directory Creation
        do {
            if !FileManager.default.fileExists(atPath: parentURL.path) {
                try FileManager.default.createDirectory(at: parentURL, withIntermediateDirectories: true, attributes: nil)
            }
            
            // Prevent folder overwrite (The 'EliteAgentWorkspace' bug fix)
            var isDir: ObjCBool = false
            if FileManager.default.fileExists(atPath: fileURL.path, isDirectory: &isDir), isDir.boolValue {
                throw AgentToolError.executionError("HATA: '\(finalPath)' bir klasördür, üzerine dosya gibi yazılamaz. Lütfen bir dosya adı belirtin (örn: WWDC.md).")
            }
            
            // v25.0: EMERGENCY SAFETY GUARD: Prevent zeroing out existing files
            let fileExists = FileManager.default.fileExists(atPath: fileURL.path)
            if fileExists && finalContent.isEmpty && !force {
                throw AgentToolError.executionError("GÜVENLİK ENGELİ: Mevcut bir dosyanın üzerine boş veri yazılamaz (truncation protection). Dosyayı kasten sıfırlamak istiyorsanız 'force: true' parametresini kullanın.")
            }
            
            // v25.0: BINARY PROTECTION: Prevent writing text to media/binary files
            let lowerPath = fileURL.path.lowercased()
            if binaryExtensions.contains(where: { lowerPath.hasSuffix($0) }) && !force {
                throw AgentToolError.executionError("GÜVENLİK ENGELİ: '\(lowerPath)' bir binary dosyasıdır. 'write_file' ile üzerine düz metin yazılamaz. Bu işlem dosyanın bozulmasına neden olur.")
            }
            
            try finalContent.write(to: fileURL, atomically: true, encoding: .utf8)

            return "File written: \(finalPath)"
        } catch {
            throw AgentToolError.executionError(error.localizedDescription)
        }
    }
}
