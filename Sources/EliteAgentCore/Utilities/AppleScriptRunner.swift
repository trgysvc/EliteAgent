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
            throw AppleScriptError.executionFailed(message)
        }
        
        return result.stringValue ?? ""
    }
}
