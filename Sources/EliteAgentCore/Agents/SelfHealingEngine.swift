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
        
        // Use pattern matching for common technical failures
        if err.contains("command not found") {
            let pkg = extractPackage(from: err) ?? "deno" // Default if unclear
            return HealingStrategy(name: "INSTALL_PKG", command: "brew install \(pkg)", description: "Missing tool '\(pkg)' detected. Attempting homebrew installation.")
        }
        
        if err.contains("permission denied") {
            // Enhanced Sudo Elevation Logic
            return HealingStrategy(name: "SUDO_ESC", command: "sudo", description: "Access restricted. Attempting to escalate permissions via AppleScript system prompt.")
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
