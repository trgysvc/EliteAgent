import Foundation

public final class ThinkParser {
    


    public static func cleanForUI(text: String) -> String {
        var cleaned = text
        // v10.5.7: More aggressive thinking/markdown removal
        cleaned = cleaned.replacingOccurrences(of: "<think>[\\s\\S]*?</think>", with: "", options: .regularExpression, range: nil)
        cleaned = cleaned.replacingOccurrences(of: "<think>[\\s\\S]*?$", with: "", options: .regularExpression, range: nil) // Handle partial streaming
        cleaned = cleaned.replacingOccurrences(of: "```(?:json)?[\\s\\S]*?```", with: "", options: .regularExpression, range: nil)
        cleaned = cleaned.replacingOccurrences(of: "```tool_code[\\s\\S]*?```", with: "", options: .regularExpression, range: nil)
        cleaned = cleaned.replacingOccurrences(of: "\\[\\s*\\{[\\s\\S]*?\\}\\s*\\]", with: "", options: .regularExpression, range: nil)
        cleaned = cleaned.replacingOccurrences(of: "<[\\|｜][^|｜]*[\\|｜]>", with: "", options: .regularExpression, range: nil)
        cleaned = cleaned.replacingOccurrences(of: "<\\/?invoke[^>]*>", with: "", options: .regularExpression, range: nil)
        
        // Standard markdown cleanup if any left
        cleaned = cleaned.replacingOccurrences(of: "```[\\s\\S]*?```", with: "", options: .regularExpression, range: nil)
        
        return cleaned.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    public static func extractJSONRobustly(_ text: String) -> String {
        // v10.5.6: Stripping markdown more flexibly (removed '^' anchor)
        var raw = text.replacingOccurrences(of: "```(?:json)?\\s*", with: "", options: .regularExpression)
                      .replacingOccurrences(of: "\\s*```", with: "", options: .regularExpression)
        
        // v10.5.6: Strip <think> blocks first to clean the raw input
        raw = raw.replacingOccurrences(of: "<think>[\\s\\S]*?</think>", with: "", options: .regularExpression)
        
        let nsString = raw as NSString
        var startIndex = -1
        var bracketCount = 0
        var opener: String = ""
        
        for i in 0..<nsString.length {
            let char = nsString.substring(with: NSRange(location: i, length: 1))
            if startIndex == -1 && (char == "{" || char == "[") {
                startIndex = i
                opener = char
                bracketCount = 1
                continue
            }
            if startIndex != -1 {
                if char == opener { bracketCount += 1 }
                else if char == (opener == "{" ? "}" : "]") { bracketCount -= 1 }
                
                if bracketCount == 0 {
                    return nsString.substring(with: NSRange(location: startIndex, length: i - startIndex + 1))
                }
            }
        }
        
        // Fallback: Repair incomplete JSON by appending missing brackets
        if startIndex != -1 && bracketCount > 0 {
            let extracted = nsString.substring(from: startIndex)
            let closer = opener == "{" ? "}" : "]"
            let repaired = extracted + String(repeating: closer, count: bracketCount)
            return repaired
        }
        
        // Final Fallback: Return as is
        return raw.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    public static func parseOutputs(from text: String) throws -> [EliteAgentOutput] {
        let cleanJSON = extractJSONRobustly(text)
        guard !cleanJSON.isEmpty, let data = cleanJSON.data(using: .utf8) else {
            throw ParserError.emptyJSON("Resmi JSON bloğu bulunamadı.")
        }
        
        let decoder = JSONDecoder()
        
        do {
            // Attempt 1: Standard Array (Multi-step)
            return try decoder.decode([EliteAgentOutput].self, from: data)
        } catch {
            do {
                // Attempt 2: Single Object (Single step)
                let single = try decoder.decode(EliteAgentOutput.self, from: data)
                return [single]
            } catch let decodeError {
                // Attempt 3: Heuristic Repair if it's almost JSON
                 AgentLogger.logAudit(level: .warn, agent: "Parser", message: "JSON Decode failed. Details: \(decodeError.localizedDescription)")
                 throw ParserError.invalidSchema("JSON şeması EliteAgent protokolüne (PRD v17.1) uymuyor: \(decodeError.localizedDescription)")
            }
        }
    }
}

public enum ParserError: Error, LocalizedError {
    case emptyJSON(String)
    case invalidSchema(String)
    
    public var errorDescription: String? {
        switch self {
        case .emptyJSON(let msg), .invalidSchema(let msg): return msg
        }
    }
}
