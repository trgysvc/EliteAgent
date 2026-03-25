import Foundation
import Combine

public enum PrivacyDecision: String, Codable, Sendable {
    case pass = "PRIVACY_PASS"
    case block = "PRIVACY_BLOCK"
    case desensitize = "PRIVACY_DESENSITIZE"
}

public actor GuardAgent: AgentProtocol {
    public let agentID: AgentID = .guard_
    public private(set) var status: AgentStatus = .idle
    public let preferredProvider: ProviderID = ProviderID(rawValue: "mlx-r1-8b")
    
    // Never access cloud provider - inherently bypassed becausefallback is empty 
    // And compile time constraint localModel: any LocalLLMProvider ensures it.
    public let fallbackProviders: [ProviderID] = [] 
    
    private let bus: SignalBus
    private let localModel: (any LocalLLMProvider)?
    
    public init(bus: SignalBus, localModel: (any LocalLLMProvider)? = nil) {
        self.bus = bus
        self.localModel = localModel
    }
    
    public func receive(_ signal: Signal) async throws {
        if signal.name == "PRIVACY_CHECK" {
            let payload = String(data: signal.payload, encoding: .utf8) ?? ""
            let (decision, cleanPayload) = await checkPrivacy(payload)
            
            let responseSignal = Signal(
                source: .guard_,
                target: .orchestrator,
                name: decision.rawValue,
                priority: .high,
                payload: cleanPayload.data(using: .utf8) ?? Data(),
                secretKey: bus.sharedSecret
            )
            
            try await bus.dispatch(responseSignal)
        }
    }
    
    private func checkPrivacy(_ payload: String) async -> (PrivacyDecision, String) {
        let engine = PrivacyRuleEngine()
        let result = engine.analyzeAndDesensitize(payload)
        
        if result.highestLevel != nil {
            AgentLogger.logAudit(level: .warn, agent: "GuardAgent", message: "Privacy Decision: DESENSITIZE | Level: \(result.highestLevel!)")
            return (.desensitize, result.cleanText)
        }
        
        AgentLogger.logAudit(level: .info, agent: "GuardAgent", message: "Privacy Decision: PASS")
        return (.pass, payload)
    }
    
    public func healthReport() -> AgentHealth {
        return AgentHealth(isHealthy: true, statusMessage: "OK")
    }
}

public struct PrivacyRuleEngine: Sendable {
    public struct Rule: Sendable {
        public let name: String
        public let pattern: String
        public let replacement: String
        public let level: SensitivityLevel
    }
    
    public let rules: [Rule] = [
        Rule(name: "CreditCard", pattern: "\\b(?:\\d[ -]*?){13,16}\\b", replacement: "[REDACTED_CC]", level: .confidential),
        Rule(name: "APIKey", pattern: "sk-[a-zA-Z0-9]{32,}", replacement: "sk-***[API_KEY]", level: .confidential),
        Rule(name: "SSN", pattern: "\\b\\d{3}-\\d{2}-\\d{4}\\b", replacement: "[REDACTED_SSN]", level: .confidential)
    ]
    
    public init() {}
    
    public func analyzeAndDesensitize(_ text: String) -> (cleanText: String, highestLevel: SensitivityLevel?) {
        var resultText = text
        var detectedLevel: SensitivityLevel? = nil
        
        for rule in rules {
            guard let regex = try? NSRegularExpression(pattern: rule.pattern, options: []) else { continue }
            let nsRange = NSRange(resultText.startIndex..<resultText.endIndex, in: resultText)
            let matches = regex.matches(in: resultText, options: [], range: nsRange)
            
            if !matches.isEmpty {
                detectedLevel = rule.level
                resultText = regex.stringByReplacingMatches(in: resultText, options: [], range: nsRange, withTemplate: rule.replacement)
            }
        }
        
        return (resultText, detectedLevel)
    }
}

