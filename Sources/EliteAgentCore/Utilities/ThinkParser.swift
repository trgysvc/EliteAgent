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
        // v13.8: UNO Pure - Priority parsing for Binary Action Format
        let binaryOutputs = tryParseUNOBinary(text)
        if !binaryOutputs.isEmpty {
            return binaryOutputs
        }
        
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
                 AgentLogger.logAudit(level: .warn, agent: "Parser", message: "JSON Decode failed. Details: \(decodeError.localizedDescription)")
                 throw ParserError.invalidSchema("JSON şeması EliteAgent protokolüne (PRD v17.1) uymuyor: \(decodeError.localizedDescription)")
            }
        }
    }

    /// v13.8: UNO Pure Binary Parser
    /// Extracts ALL CALL([UBID]) WITH { ... } blocks directly, handling nested braces.
    private static func tryParseUNOBinary(_ text: String) -> [EliteAgentOutput] {
        var results: [EliteAgentOutput] = []
        let nsString = text as NSString
        let pattern = "CALL\\(\\[(\\d+)\\]\\)\\s*WITH\\s*\\{"
        
        guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else { return [] }
        let matches = regex.matches(in: text, options: [], range: NSRange(location: 0, length: text.utf16.count))
        
        for match in matches {
            let ubidStr = nsString.substring(with: match.range(at: 1))
            guard let ubid = Int(ubidStr) else { continue }
            
            // Start scanning for the balancing brace from the start of the '{'
            let paramsStart = match.range.lowerBound + (nsString.substring(with: match.range).range(of: "{")?.upperBound.utf16Offset(in: nsString.substring(with: match.range)) ?? 0) - 1
            
            var bracketCount = 0
            var foundEnd = false
            var paramsStr = ""
            
            if paramsStart < nsString.length {
                for j in paramsStart..<nsString.length {
                    let char = nsString.substring(with: NSRange(location: j, length: 1))
                    if char == "{" {
                        bracketCount += 1
                    } else if char == "}" {
                        bracketCount -= 1
                        if bracketCount == 0 {
                            paramsStr = nsString.substring(with: NSRange(location: paramsStart, length: j - paramsStart + 1))
                            foundEnd = true
                            break
                        }
                    }
                }
            }
            
            if foundEnd {
                var params: [String: AnyCodable] = [:]
                if let data = paramsStr.data(using: .utf8),
                   let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                    params = json.mapValues { AnyCodable($0) }
                } else {
                    AgentLogger.logAudit(level: .warn, agent: "Parser", message: "Failed to parse JSON params for UBID \(ubid): \(paramsStr)")
                }
                
                results.append(EliteAgentOutput(type: .tool_call, thought: "UNO Binary Action Triggered", ubid: ubid, params: params))
            }
        }
        
        if !results.isEmpty {
            AgentLogger.logInfo("[UNO-Pure] Binary Action Found: \(results.count) steps")
        }
        if !results.isEmpty {
            AgentLogger.logInfo("[UNO-Pure] Binary Action Found: \(results.count) steps")
            return results
        }
        
        // v19.7.11: DONE Signal Detection
        if text.contains("<final>DONE</final>") {
            AgentLogger.logInfo("[UNO-Pure] DONE signal detected.")
            return [EliteAgentOutput(type: .response, content: "TASK_DONE")]
        }
        
        return []
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
