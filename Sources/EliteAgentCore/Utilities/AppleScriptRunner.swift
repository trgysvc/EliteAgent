import Foundation

public enum AppleScriptError: Error, Sendable {
    case initializationFailed
    case executionFailed(String)
}

public actor AppleScriptRunner {
    public static let shared = AppleScriptRunner()
    
    private init() {}
    
    public func execute(source: String) async throws -> String {
        guard let script = NSAppleScript(source: source) else {
            throw AppleScriptError.initializationFailed
        }
        
        var errorDict: NSDictionary?
        let result = script.executeAndReturnError(&errorDict)
        
        if let error = errorDict {
            let message = error["NSAppleScriptErrorMessage"] as? String ?? "Unknown AppleScript error"
            let errorCode = error["NSAppleScriptErrorNumber"] as? Int ?? -1
            
            var diagnostic = "AppleScript Error \(errorCode): \(message)"
            if errorCode == -43 {
                diagnostic += "\n[DIAGNOSTIC] File or Application not found. Check if the target app is installed and EliteAgent has Automation permissions."
            } else if errorCode == -1728 || errorCode == 0 {
                diagnostic += "\n[DIAGNOSTIC] Protocol/System Events error. This usually means macOS Privacy & Security blocked the action. Please check Settings > Privacy & Security > Automation for EliteAgent."
            }
            
            print("[ORCHESTRATOR] \(diagnostic)")
            throw AppleScriptError.executionFailed(diagnostic)
        }
        
        return result.stringValue ?? ""
    }
}
