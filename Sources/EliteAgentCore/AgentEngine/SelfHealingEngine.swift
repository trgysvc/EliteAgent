import Foundation

public struct HealingStrategy: Sendable {
    public let name: String
    public let command: String?
    public let description: String
}

public actor SelfHealingEngine {
    public static let shared = SelfHealingEngine()
    
    private var retryCounts: [String: Int] = [:]
    private let maxRetries = 5
    
    private init() {}
    
    public func analyze(error: String, tool: String) -> HealingStrategy? {
        let err = error.lowercased()
        
        // macOS TCC / Automation permission block (AppleScript Error 0 or -1743)
        if err.contains("applescript error 0") || err.contains("error 0:") || err.contains("-1743") {
            return HealingStrategy(
                name: "TCC_PERMISSION",
                command: nil,
                description: """
                [PERMISSION ERROR] macOS blocked EliteAgent from controlling this application.
                REMEDY: Go to System Settings > Privacy & Security > Automation > EliteAgent and enable permissions for the target app (Messages, WhatsApp, Calendar, etc.).
                """
            )
        }
        
        // AppleScript Error -43: File/Application not found (FSFindFolder failure in WhatsApp)
        if err.contains("-43") || err.contains("fsfind") || err.contains("error=-43") {
            return HealingStrategy(
                name: "APP_NOT_FOUND",
                command: nil,
                description: """
                [APP ERROR] Target application not found or legacy API call failed (FSFindFolder -43).
                For WhatsApp, this is usually bypassed using the URL Scheme method. Verify if the app is installed.
                """
            )
        }
        
        // XPC connection failure
        if err.contains("os/kern") || err.contains("0x5") || err.contains("xpc") {
            return HealingStrategy(
                name: "XPC_FAILURE",
                command: nil,
                description: """
                [XPC ERROR] Service connection failed. Ensure EliteAgent is running without sandbox restrictions.
                This error used to originate from ShellTool XPC service — now native Process() is used directly.
                """
            )
        }
        
        // iMessage: buddy not found by name (-1728)
        if err.contains("-1728") || err.contains("buddy") {
            return HealingStrategy(
                name: "IMESSAGE_HANDLE",
                command: nil,
                description: """
                [iMESSAGE ERROR] Person not found by name. For iMessage, use 'participant' instead of 'buddy'.
                Provide the recipient as a phone number (+1XXXXXXXXXX) or Apple ID email instead of a display name.
                """
            )
        }
        
        // Shell glob/quoting failure: & and special chars not quoted correctly
        if err.contains("no matches found") || (err.contains("no such file or directory") && (err.contains("shell_error") || err.contains("[shell_error]"))) {
            return HealingStrategy(
                name: "SHELL_QUOTE_ERROR",
                command: nil,
                description: """
                [SHELL QUOTE ERROR] The file path in your command was incorrectly escaped.
                ROOT CAUSE: Using backslashes (\\) in paths with '&' or spaces breaks the shell.
                REMEDY: Wrap ALL file paths in SINGLE QUOTES ('):
                  WRONG: cp -r /path/Sonar\\-&GlobalGrooves/* /dest/
                  CORRECT: cp -r '/path/Sonar-&GlobalGrooves/'* '/dest/'
                IMPORTANT: Verify folder existence with 'ls' before copying.
                """
            )
        }
        
        // Command not found
        if err.contains("command not found") {
            let pkg = extractPackage(from: err) ?? "deno"
            return HealingStrategy(name: "INSTALL_PKG", command: "brew install \(pkg)", description: "Missing tool '\(pkg)' detected. Attempting homebrew installation.")
        }
        
        if err.contains("permission denied") {
            return HealingStrategy(name: "SUDO_ESC", command: nil, description: "Access restricted. Check file permissions or run with appropriate privileges.")
        }
        
        if err.contains("port in use") || err.contains("address already in use") {
            return HealingStrategy(name: "FREE_PORT", command: "killall -9 node", description: "Port conflict detected. Attempting to clear existing processes.")
        }
        
        return nil
    }
    
    public func canRetry(error: String) -> Bool {
        let count = retryCounts[error] ?? 0
        return count < maxRetries
    }
    
    public func recordRetry(error: String) {
        retryCounts[error, default: 0] += 1
    }
    
    private func extractPackage(from error: String) -> String? {
        // Simple regex or string splitting to find the command name
        // e.g., "sh: line 1: htop: command not found"
        let parts = error.split(separator: ":")
        if parts.count > 2 {
            return parts[2].trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return nil
    }
}
