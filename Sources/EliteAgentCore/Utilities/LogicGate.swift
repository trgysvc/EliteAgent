import Foundation

public struct SafetyRisk: Sendable {
    public let isDangerous: Bool
    public let reason: String?
}

public final class LogicGate: Sendable {
    public static let shared = LogicGate()
    
    private let restrictedPatterns = [
        "rm -rf /",
        "rm -rf ~",
        "chmod -R 777",
        "sudo ",
        "> /etc/",
        "mv / ",
        "killall -9 loginwindow"
    ]
    
    private init() {}
    
    public func check(command: String) -> SafetyRisk {
        for pattern in restrictedPatterns {
            if command.lowercased().contains(pattern.lowercased()) {
                return SafetyRisk(isDangerous: true, reason: "Command contains restricted pattern: \(pattern)")
            }
        }
        
        // Check for suspicious combinations
        if (command.contains("curl") || command.contains("wget")) && command.contains("| sh") {
            return SafetyRisk(isDangerous: true, reason: "Piping remote scripts directly to shell is restricted.")
        }
        
        return SafetyRisk(isDangerous: false, reason: nil)
    }
}
