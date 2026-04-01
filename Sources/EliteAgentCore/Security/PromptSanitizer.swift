import Foundation

public struct PromptSanitizer: Sendable {
    public let flaggedPatterns = [
        "ignore previous instructions",
        "you are now",
        "disregard your",
        "act as if",
        "forget everything"
    ]
    
    public init() {}
    
    public func sanitize(prompt: String, agentID: String, bus: SignalBus?) async -> Bool {
        let lowercasedPrompt = prompt.lowercased()
        
        for pattern in flaggedPatterns {
            if lowercasedPrompt.contains(pattern) {
                let logPath = PathConfiguration.shared.logsURL
                    .appendingPathComponent("security.log")
                
                // Ensure directory exists
                let dir = logPath.deletingLastPathComponent()
                try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
                
                // Utilize native isolated logger
                let message = "Prompt injection attempt detected: matched '\(pattern)'"
                AgentLogger.logSecurity(level: .error, agent: agentID, message: message)
                
                // Emit SECURITY_FLAG
                if let bus = bus {
                    let payloadDict = ["type": "SECURITY_FLAG", "agent": agentID, "reason": message]
                    let payloadData = (try? JSONSerialization.data(withJSONObject: payloadDict)) ?? Data()
                    let signal = Signal(
                        source: .orchestrator, // Emitted securely from bounds
                        target: .orchestrator,
                        name: "SECURITY_FLAG",
                        priority: .high,
                        payload: payloadData,
                        secretKey: bus.sharedSecret
                    )
                    try? await bus.dispatch(signal)
                }
                
                return false // Sanitize failed, prompt rejected
            }
        }
        return true // Safe
    }
}
