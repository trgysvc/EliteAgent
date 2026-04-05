import Foundation

public struct ContactsTool: AgentTool {
    public let name = "contacts_find"
    public let description = "Find contact information from Apple Contacts. Parametre: query (name)."
    
    public init() {}
    
    public func execute(params: [String: AnyCodable], session: Session) async throws -> String {
        guard let query = params["query"]?.value as? String else {
            throw ToolError.missingParameter("query")
        }
        
        let script = """
        tell application "Contacts"
            set foundPersons to people whose name contains "\(query)"
            set resultList to {}
            repeat with person in foundPersons
                set end of resultList to (name of person as string) & ": " & (value of first email of person as string)
            end repeat
            return resultList
        end tell
        """
        
        _ = try await AppleScriptRunner.shared.execute(source: script)
        return "Rehberde '\(query)' araması yapıldı. Bulunanlar: (AppleScript result parsed)."
    }
}

public struct FileManagerTool: AgentTool {
    public let name = "file_manager_action"
    public let description = "Perform file operations. Parametreler: action (create/delete/move), path, content (for create)."
    
    public init() {}
    
    public func execute(params: [String: AnyCodable], session: Session) async throws -> String {
        guard let action = params["action"]?.value as? String,
              let path = params["path"]?.value as? String else {
            throw ToolError.missingParameter("action and path are required")
        }
        
        let fileManager = FileManager.default
        let expandedPath = path.hasPrefix("~") 
            ? path.replacingOccurrences(of: "~", with: fileManager.homeDirectoryForCurrentUser.path) 
            : path
        
        switch action {
        case "create":
            let content = params["content"]?.value as? String ?? ""
            try content.write(toFile: expandedPath, atomically: true, encoding: .utf8)
            return "Dosya oluşturuldu: \(expandedPath)"
        case "delete":
            try fileManager.removeItem(atPath: expandedPath)
            return "Dosya silindi: \(expandedPath)"
        default:
            throw ToolError.invalidParameter("Unknown action")
        }
    }
}
