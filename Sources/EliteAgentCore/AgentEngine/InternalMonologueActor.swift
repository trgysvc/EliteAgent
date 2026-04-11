import Foundation

public struct Strategy: Codable, Sendable {
    public let name: String // "SAFE", "FAST", "COMPREHENSIVE"
    public let plan: String
    public let risk: String
}

public actor InternalMonologueActor {
    public static let shared = InternalMonologueActor()
    
    private init() {}
    
    public func simulate(task: String, context: String, provider: CloudProvider) async throws -> Strategy {
        let systemPrompt = """
        Sen Elite Agent Reasoning Engine'sin.
        Görevi analiz et ve 3 farklı çözüm stratejisi üret. 
        
        Yanıtın SADECE şu formatta olmalı:
        SELECTED: [NAME]
        PLAN: [PLAN_CONTENT]
        RISK: [RISK_LEVEL]
        
        NAME şunlardan biri olmalı: SAFE, FAST, COMPREHENSIVE
        """
        
        let request = CompletionRequest(
            taskID: UUID().uuidString,
            systemPrompt: systemPrompt,
            messages: [Message(role: "user", content: "GÖREV: \(task)\n\n\(context)")],
            maxTokens: 1000,
            sensitivityLevel: .internal,
            complexity: 5
        )
        
        let response = try await provider.complete(request, useSafeMode: false)
        
        // v13.8: UNO Pure - Delimited Parsing (No JSON Artıkları)
        let content = response.content
        let lines = content.components(separatedBy: .newlines)
        
        var selected = "SAFE"
        var plan = "Proceed with standard cautious steps."
        var risk = "Low"
        
        for line in lines {
            if line.hasPrefix("SELECTED:"), let val = line.split(separator: ":", maxSplits: 1).last {
                selected = val.trimmingCharacters(in: .whitespacesAndNewlines)
            } else if line.hasPrefix("PLAN:"), let val = line.split(separator: ":", maxSplits: 1).last {
                plan = val.trimmingCharacters(in: .whitespacesAndNewlines)
            } else if line.hasPrefix("RISK:"), let val = line.split(separator: ":", maxSplits: 1).last {
                risk = val.trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }
        
        return Strategy(name: selected, plan: plan, risk: risk)
    }
}
