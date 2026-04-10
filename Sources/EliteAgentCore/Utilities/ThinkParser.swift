import Foundation

public final class ThinkParser {
    


    public static func cleanForUI(text: String) -> String {
        var cleaned = text
        // v11.9: Better balance between cleaning and preserving data
        cleaned = cleaned.replacingOccurrences(of: "<think>[\\s\\S]*?</think>", with: "", options: .regularExpression, range: nil)
        cleaned = cleaned.replacingOccurrences(of: "<think>[\\s\\S]*?$", with: "", options: .regularExpression, range: nil)
        cleaned = cleaned.replacingOccurrences(of: "```(?:json)?[\\s\\S]*?```", with: "", options: .regularExpression, range: nil)
        
        // Only strip arrays from UI if they look like ToolCall steps (v11.9 refinement)
        cleaned = cleaned.replacingOccurrences(of: "\\[\\s*\\{[\\s\\S]*?\"(toolID|action|stepID)\"[\\s\\S]*?\\}\\s*\\]", with: "", options: .regularExpression, range: nil)
        
        // Strip single tool call objects from UI
        cleaned = cleaned.replacingOccurrences(of: "\\{\\s*\"(type|toolID|action)\"\\s*:\\s*\"(tool_call|[^\"]+)\"[\\s\\S]*?\\}", with: "", options: .regularExpression, range: nil)
        
        cleaned = cleaned.replacingOccurrences(of: "<[\\|｜][^|｜]*[\\|｜]>", with: "", options: .regularExpression, range: nil)
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
                // Attempt 3: Heuristic Repair (Regex recovery for 'result' field)
                let str = String(data: data, encoding: .utf8) ?? ""
                
                // v11.7: Aggressive Tool Call Recovery
                if let _ = str.range(of: "\"toolID\"\\s*:\\s*\"([^\"]*)\"", options: .regularExpression) {
                    let pattern = "\"toolID\"\\s*:\\s*\"([^\"]*)\""
                    if let regex = try? NSRegularExpression(pattern: pattern, options: []),
                       let match = regex.firstMatch(in: str, options: [], range: NSRange(location: 0, length: str.utf16.count)) {
                        let toolID = (str as NSString).substring(with: match.range(at: 1))
                        // Try to find params as well (crude but effective fallback)
                        var params: [String: AnyCodable] = [:]
                        if let paramsMatch = str.range(of: "\"params\"\\s*:\\s*(\\{[^}]*\\})", options: .regularExpression) {
                            let pStr = String(str[paramsMatch].split(separator: ":", maxSplits: 1).last ?? "{}")
                            if let pData = pStr.data(using: .utf8), let pJson = try? JSONSerialization.jsonObject(with: pData) as? [String: Any] {
                                params = pJson.mapValues { AnyCodable($0) }
                            }
                        }
                        return [EliteAgentOutput(type: .tool_call, thought: "Heuristic Recovery", action: toolID, params: params)]
                    }
                }

                if let _ = str.range(of: "\"result\"\\s*:\\s*\"([^\"]*)\"", options: .regularExpression) {
                    let pattern = "\"result\"\\s*:\\s*\"([^\"]*)\""
                    if let regex = try? NSRegularExpression(pattern: pattern, options: []),
                       let match = regex.firstMatch(in: str, options: [], range: NSRange(location: 0, length: str.utf16.count)) {
                        let content = (str as NSString).substring(with: match.range(at: 1))
                        return [EliteAgentOutput(type: .response, thought: "Heuristic Recovery", content: content)]
                    }
                }
                
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
