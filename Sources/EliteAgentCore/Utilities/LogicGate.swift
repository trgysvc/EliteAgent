import Foundation

public struct SafetyRisk: Sendable {
    public let isDangerous: Bool
    public let reason: String?
}

public final class LogicGate: Sendable {
    public static let shared = LogicGate()
    
    private let blacklist = [
        "rm -rf /", "rm -rf ~", "chmod -R 777", "sudo ", "> /etc/", 
        "killall -9 loginwindow", "shutdown", "reboot", "format"
    ]
    
    private let safeWhitelist = [
        "ls", "pwd", "whoami", "git status", "git log", "git branch",
        "swift build", "swift run", "swift test", "xcodebuild -version",
        "cat ", "grep ", "find ", "mkdir ", "touch ", "cp ", "mv "
    ]
    
    private let suggestions: [String: String] = [
        "thermalmonitord": "Use 'ProcessInfo.processInfo.thermalState' (Swift) instead of spying on PID 404.",
        "host_statistics64": "Use 'ProcessInfo.processInfo.physicalMemory' for memory stats.",
        "top": "Use 'ProcessInfo.processInfo.processorCount' for basic CPU info.",
        "curl | sh": "Piping remote scripts directly is restricted. Review source first.",
        "afplay": "Audio playback/analysis via shell is restricted. Use the 'music_dna' tool for AI-powered audio intelligence."
    ]
    
    private let allowedResearchDomains = [
        "api.serper.dev", "google.com", "brave.com", "duckduckgo.com", "wikipedia.org"
    ]
    
    private init() {}
    
    public func check(command: String) -> SafetyRisk {
        let cmd = command.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        
        // 1. Blacklist Check (High Priority)
        for pattern in blacklist {
            if cmd.contains(pattern.lowercased()) {
                return SafetyRisk(isDangerous: true, reason: "Command contains restricted destructive pattern: \(pattern)")
            }
        }
        
        // 2. Suggestion/Sandbox Check
        for (key, recommendation) in suggestions {
            if cmd.contains(key) {
                return SafetyRisk(isDangerous: true, reason: "Sandbox Restriction: Accessing \(key) is unsafe. Suggestion: \(recommendation)")
            }
        }
        
        // 3. Networking Commands Whitelist (Research Mode Hardening)
        if cmd.contains("curl") || cmd.contains("wget") {
            let isDomainAllowed = allowedResearchDomains.contains { domain in
                cmd.contains(domain)
            }
            
            if !isDomainAllowed {
                return SafetyRisk(isDangerous: true, reason: "Network Command Restricted: Only research-whitelisted domains are allowed (e.g., google.com, serper.dev).")
            }
            print("[LOGICGATE] Authorized Research Command detected.")
        }
        
        // 4. Whitelist Heuristic & Failsafe
        let isWhitelisted = safeWhitelist.contains { pattern in
            cmd.hasPrefix(pattern.lowercased())
        }
        
        if isWhitelisted || cmd.starts(with: "./") {
             return SafetyRisk(isDangerous: false, reason: nil)
        }
        
        return SafetyRisk(isDangerous: false, reason: "Unrecognized command but no immediate danger found.")
    }
}
