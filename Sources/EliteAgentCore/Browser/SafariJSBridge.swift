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
            if (count of windows) > 0 then
                set currentTab to current tab of front window
                try
                    return do JavaScript "\(escapedScript)" in currentTab
                on error errMsg
                    return "JS_ERROR: " & errMsg
                end try
            else
                return "NO_WINDOW"
            end if
        end tell
        """
        
        return try execute(source)
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
        return try execute(source)
    }

    public static func listTabs() throws -> String {
        let source = """
        set tabList to ""
        tell application "Safari"
            set winCount to count of windows
            repeat with w from 1 to winCount
                set tCount to count of tabs of window w
                repeat with t from 1 to tCount
                    set tName to name of tab t of window w
                    set tURL to URL of tab t of window w
                    set tabList to tabList & w & "|" & t & "|" & tName & "|" & tURL & "\n"
                end repeat
            end repeat
        end tell
        return tabList
        """
        return try execute(source)
    }

    public static func switchToTab(windowIndex: Int, tabIndex: Int) throws {
        let source = """
        tell application "Safari"
            set index of window \(windowIndex) to 1
            set current tab of window 1 to tab \(tabIndex) of window 1
            activate
        end tell
        """
        _ = try execute(source)
    }

    private static func execute(_ source: String) throws -> String {
        var errorDict: NSDictionary?
        guard let appleScript = NSAppleScript(source: source) else {
            throw SafariJSError.executionFailed("Failed to initialize NSAppleScript")
        }
        
        let result = appleScript.executeAndReturnError(&errorDict)
        if let error = errorDict {
            let msg = error[NSAppleScript.errorMessage] as? String ?? error.description
            throw SafariJSError.executionFailed(msg)
        }
        return result.stringValue ?? ""
    }
}
