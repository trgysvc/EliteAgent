import Foundation

public enum SafariJSError: Error, CustomStringConvertible, Sendable {
    case executionFailed(String)
    
    public var description: String {
        switch self {
        case .executionFailed(let msg): return "Safari AppleScript Execution Failed: \(msg)"
        }
    }
}

public struct SafariJSBridge: Sendable {
    public static func evaluate(_ script: String) throws -> String {
        let escapedScript = script.replacingOccurrences(of: "\\", with: "\\\\")
                                  .replacingOccurrences(of: "\"", with: "\\\"")
        let source = """
        tell application "Safari"
            if (count of documents) > 0 then
                set currentTab to current tab of front window
                return do JavaScript "\(escapedScript)" in currentTab
            else
                return ""
            end if
        end tell
        """
        
        var errorDict: NSDictionary?
        if let appleScript = NSAppleScript(source: source) {
            let result = appleScript.executeAndReturnError(&errorDict)
            if let error = errorDict {
                throw SafariJSError.executionFailed(error.description)
            }
            return result.stringValue ?? ""
        } else {
            throw SafariJSError.executionFailed("Failed to initialize NSAppleScript")
        }
    }
    
    public static func getCurrentURL() throws -> String {
        let source = """
        tell application "Safari"
            if (count of documents) > 0 then
                return URL of document 1
            else
                return ""
            end if
        end tell
        """
        var errorDict: NSDictionary?
        if let appleScript = NSAppleScript(source: source) {
            let result = appleScript.executeAndReturnError(&errorDict)
            if let error = errorDict {
                throw SafariJSError.executionFailed(error.description)
            }
            return result.stringValue ?? ""
        }
        return ""
    }
}
