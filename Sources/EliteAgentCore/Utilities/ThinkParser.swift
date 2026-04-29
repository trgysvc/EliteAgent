import Foundation

public final class ThinkParser {
    
    /// UNO Pure: Cleans the output for UI display by stripping internal protocol tags and thinking blocks.
    public static func cleanForUI(text: String) -> String {
        var cleaned = text
        // v11.9: Strip <think> blocks
        cleaned = cleaned.replacingOccurrences(of: "<think>[\\s\\S]*?</think>", with: "", options: .regularExpression, range: nil)
        cleaned = cleaned.replacingOccurrences(of: "<think>[\\s\\S]*?$", with: "", options: .regularExpression, range: nil)
        
        // v20.6: Aggressive Hallucination Stripping
        // Strip common hallucinated technical headers
        let technicalPatterns = [
            "THINK>.*$",
            "Planlanıyor.*$",
            "Planlıyorum.*$",
            "Adım .*$",
            "Observation:.*$",
            "Sistem:.*$",
            "Dahili Rapor:.*$",
            "Analiz:*$",
            "Kernel Observation:.*$"
        ]
        
        for pattern in technicalPatterns {
            cleaned = cleaned.replacingOccurrences(of: pattern, with: "", options: [.regularExpression, .caseInsensitive], range: nil)
        }
        
        // UNO Pure: Strip protocol CALL blocks from UI
        cleaned = cleaned.replacingOccurrences(of: "CALL\\(\\[\\d+\\]\\)\\s*WITH\\s*\\{[\\s\\S]*?\\}", with: "", options: .regularExpression, range: nil)
        
        // Strip final/signal tags
        cleaned = cleaned.replacingOccurrences(of: "<final>[\\s\\S]*?</final>", with: "", options: .regularExpression, range: nil)
        cleaned = cleaned.replacingOccurrences(of: "DONE", with: "", options: .caseInsensitive, range: nil)
        cleaned = cleaned.replacingOccurrences(of: "<[\\|｜][^|｜]*[\\|｜]>", with: "", options: .regularExpression, range: nil)
        
        return cleaned.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// UNO Pure: Master entry point for parsing model outputs.
    /// Strictly enforces Binary Action signatures. NO JSON fallbacks.
    public static func parseOutputs(from text: String) throws -> [EliteAgentOutput] {
        // v13.8: UNO Pure - Priority parsing for Binary Action Format
        let binaryOutputs = tryParseUNOBinary(text)
        if !binaryOutputs.isEmpty {
            return binaryOutputs
        }
        
        // v19.7.11: DONE Signal Detection (Task Completion)
        if text.contains("<final>DONE</final>") || text.contains("DONE") {
            AgentLogger.logInfo("[UNO-Pure] DONE signal detected.")
            return [EliteAgentOutput(type: .response, content: "TASK_DONE")]
        }
        
        // If no binary signatures are found and it's not a clear DONE signal,
        // we check if it's just a conversation turn.
        if !text.contains("CALL(") {
             return [EliteAgentOutput(type: .response, content: text)]
        }
        
        throw ParserError.protocolMismatch("UNO Protokol İmzası (CALL[UBID]) bulunamadı veya hatalı formatta.")
    }

    /// v25.0: UNO Pure Standardized Parameter Extractor
    /// Completely bypasses JSONSerialization to avoid recurring quote escaping failures.
    /// Standardizes communication by extracting key-value pairs directly from the signal.
    private static func extractUNOParsedParameters(_ text: String) -> [String: AnyCodable] {
        var params: [String: AnyCodable] = [:]
        
        // v25.0 Pattern: Matches "key": "value" pairs with support for complex nested quotes
        // We use a non-greedy scan that respects the binary-like structure of UNO signals.
        let pattern = "\"([^\"]+)\"\\s*:\\s*\"([\\s\\S]*?)\"(?=\\s*[,\\}])"
        guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else { return [:] }
        
        let nsString = text as NSString
        let matches = regex.matches(in: text, options: [], range: NSRange(location: 0, length: text.utf16.count))
        
        for match in matches {
            let key = nsString.substring(with: match.range(at: 1))
            var value = nsString.substring(with: match.range(at: 2))
            
            // v25.0: Explicit Sanitization for Binary Integrity
            // We only unescape what is absolutely necessary for the tool execution
            value = value.replacingOccurrences(of: "\\\"", with: "\"")
            value = value.replacingOccurrences(of: "\\'", with: "'")
            value = value.replacingOccurrences(of: "\\n", with: "\n")
            
            params[key] = AnyCodable(value)
        }
        
        return params
    }

    /// v13.8: UNO Pure Binary Parser
    /// Extracts ALL CALL([UBID]) WITH { ... } blocks directly, handling nested structures for parameters.
    private static func tryParseUNOBinary(_ text: String) -> [EliteAgentOutput] {
        var results: [EliteAgentOutput] = []
        let nsString = text as NSString
        let pattern = "CALL\\(\\[?(\\d+)\\]?\\)\\s*WITH\\s*\\{"
        
        guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else { return [] }
        let matches = regex.matches(in: text, options: [], range: NSRange(location: 0, length: text.utf16.count))
        
        for match in matches {
            let ubidStr = nsString.substring(with: match.range(at: 1))
            guard let ubid = Int128(ubidStr) else { continue }
            
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
                // v25.0: Transition to Standardized Parameter Extraction (No JSON Serialization)
                let params = extractUNOParsedParameters(paramsStr)
                
                if params.isEmpty && paramsStr.count > 4 {
                    AgentLogger.logAudit(level: .warn, agent: "Parser", message: "🛡 [UNO-PURE] Fallback required for complex params: \(paramsStr)")
                }
                
                results.append(EliteAgentOutput(type: .tool_call, thought: "UNO Binary Action Triggered", ubid: ubid, params: params))
            }
        }
        
        if !results.isEmpty {
            AgentLogger.logInfo("[UNO-Pure] Binary Action(s) successfully extracted: \(results.count) steps")
            return results
        }
        
        return []
    }
}

public enum ParserError: Error, LocalizedError {
    case protocolMismatch(String)
    case emptyOutput(String)
    
    public var errorDescription: String? {
        switch self {
        case .protocolMismatch(let msg), .emptyOutput(let msg): return msg
        }
    }
}
