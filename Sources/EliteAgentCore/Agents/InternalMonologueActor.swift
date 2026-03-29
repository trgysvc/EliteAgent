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
        Görevi analiz et ve 3 farklı çözüm stratejisi üret:
        1. **SAFE**: En düşük riskli, adımları doğrulayan yol.
        2. **FAST**: En hızlı, doğrudan hedefe giden yol.
        3. **COMPREHENSIVE**: En detaylı, tüm olasılıkları kapsayan yol.
        
        Ardından bu 3 yolu "Öz-Eleştiri" (Self-Criticism) süzgecinden geçir ve en uygun olanı seç.
        
        Yanıt SADECE JSON formatında olmalı:
        {
          "strategies": [
            {"name": "SAFE", "plan": "...", "risk": "..."},
            {"name": "FAST", "plan": "...", "risk": "..."},
            {"name": "COMPREHENSIVE", "plan": "...", "risk": "..."}
          ],
          "selected": "COMPREHENSIVE",
          "critique": "..."
        }
        """
        
        let request = CompletionRequest(
            taskID: UUID().uuidString,
            systemPrompt: systemPrompt,
            messages: [Message(role: "user", content: "GÖREV: \(task)\n\n\(context)")],
            maxTokens: 1500,
            sensitivityLevel: .internal,
            complexity: 5
        )
        
        let response = try await provider.complete(request)
        
        // Extract raw JSON — LLMs often wrap output in ```json ... ``` fences
        let rawJSON = Self.extractJSON(from: response.content)
        
        guard let data = rawJSON.data(using: .utf8),
              let result = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let strategies = result["strategies"] as? [[String: Any]],
              let selectedName = result["selected"] as? String,
              let selectedDict = strategies.first(where: { ($0["name"] as? String) == selectedName }) else {
            // Fallback to safe
            return Strategy(name: "SAFE", plan: "Proceed with standard cautious steps.", risk: "Low")
        }
        
        return Strategy(
            name: selectedName,
            plan: selectedDict["plan"] as? String ?? "",
            risk: selectedDict["risk"] as? String ?? ""
        )
    }
    
    /// Strips ```json / ``` markdown fences and extracts the first JSON object.
    /// Conforms to defensive parsing best-practice for LLM outputs.
    static func extractJSON(from text: String) -> String {
        var cleaned = text.trimmingCharacters(in: .whitespacesAndNewlines)
        
        // Remove ```json ... ``` or ``` ... ``` fences if present
        if cleaned.hasPrefix("```") {
            let lines = cleaned.components(separatedBy: "\n")
            let body = lines.dropFirst().dropLast().joined(separator: "\n")
            cleaned = body.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        
        // Extract the outermost {...} block
        guard let start = cleaned.firstIndex(of: "{"),
              let end = cleaned.lastIndex(of: "}") else {
            return cleaned
        }
        return String(cleaned[start...end])
    }
}
