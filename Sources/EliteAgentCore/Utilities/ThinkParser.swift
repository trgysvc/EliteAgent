import Foundation

public final class ThinkParser {
    public static func parse(_ text: String) -> [ThinkBlock] {
        var blocks: [ThinkBlock] = []
        
        // v9.9: Patterns tracking
        let thinkPattern = "<think>([\\s\\S]*?)</think>"
        let finalPattern = "<final>([\\s\\S]*?)</final>"
        // v9.9.3: Improved regex to handle boundaries between multiple unwrapped blocks
        let toolPattern = "(?:```)?tool_code\\s*([\\s\\S]*?)(?=```|tool_code|$)"
        
        let thinkRegex = try? NSRegularExpression(pattern: thinkPattern, options: [])
        let finalRegex = try? NSRegularExpression(pattern: finalPattern, options: [])
        let toolRegex = try? NSRegularExpression(pattern: toolPattern, options: [])
        
        let nsString = text as NSString
        let range = NSRange(location: 0, length: nsString.length)
        
        let thinkMatches = thinkRegex?.matches(in: text, options: [], range: range) ?? []
        let finalMatches = finalRegex?.matches(in: text, options: [], range: range) ?? []
        let toolMatches = toolRegex?.matches(in: text, options: [], range: range) ?? []
        
        // 1. Precise Matching: Tags exist
        for thinkMatch in thinkMatches {
            let thought = nsString.substring(with: thinkMatch.range(at: 1)).trimmingCharacters(in: .whitespacesAndNewlines)
            blocks.append(ThinkBlock(thought: thought, toolCall: nil))
        }
        
        // v9.9.2: Capture ALL tool calls found with the regex
        for toolMatch in toolMatches {
            let captured = nsString.substring(with: toolMatch.range(at: 1))
            let toolContent = extractJSONrobustly(captured)
            if let toolCall = tryParseToolCall(from: toolContent) {
                blocks.append(ThinkBlock(thought: "", toolCall: toolCall))
            }
        }
        
        for finalMatch in finalMatches {
            let content = nsString.substring(with: finalMatch.range(at: 1)).trimmingCharacters(in: .whitespacesAndNewlines)
            // Check if <final> contains a tool call or report instead of plain text
            if let toolCall = tryParseToolCall(from: extractJSONrobustly(content)) {
                blocks.append(ThinkBlock(thought: "", toolCall: toolCall))
            } else {
                blocks.append(ThinkBlock(thought: content, toolCall: nil))
            }
        }
        
        // 2. Last Resort: Robust JSON extraction on full text
        if blocks.isEmpty {
            let extracted = extractJSONrobustly(text)
            if let toolCall = tryParseToolCall(from: extracted) {
                blocks.append(ThinkBlock(thought: "", toolCall: toolCall))
            } else if !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                blocks.append(ThinkBlock(thought: text, toolCall: nil))
            }
        }
        
        #if DEBUG
        if UserDefaults.standard.bool(forKey: "debugParser") {
            print("[ThinkParser] Input: \(text.prefix(100))...")
            print("[ThinkParser] Parsed Blocks: \(blocks.count)")
        }
        #endif
        
        return blocks
    }

    public static func extractJSONrobustly(_ input: String) -> String {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        
        // Level 1: Direct JSON
        if trimmed.hasPrefix("{") && trimmed.hasSuffix("}") {
            return trimmed
        }
        
        // Level 2: Markdown Code Blocks (json, tool_code, or plain)
        let patterns = [
            "```json([\\s\\S]*?)```",
            "```tool_code([\\s\\S]*?)```",
            "```([\\s\\S]*?)```"
        ]
        
        for pattern in patterns {
            if let regex = try? NSRegularExpression(pattern: pattern, options: []),
               let match = regex.firstMatch(in: input, options: [], range: NSRange(input.startIndex..., in: input)) {
                let content = (input as NSString).substring(with: match.range(at: 1))
                return content.trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }
        
        // Level 3: Regex Search for outer braces
        if let first = input.firstIndex(of: "{"),
           let last = input.lastIndex(of: "}") {
            return String(input[first...last])
        }
        
        return trimmed
    }

    private static func tryParseToolCall(from content: String) -> ToolCall? {
        // v9.9.1: Special handling for Premium Research Reports (Strict Validation)
        let isReport = isResearchReport(content)
        #if DEBUG
        if UserDefaults.standard.bool(forKey: "debugParser") {
            AgentLogger.logInfo("🔍 Result: \(isReport ? "RESEARCH" : "PLAIN")", agent: "ThinkParser")
        }
        #endif
        
        if isReport {
            return nil 
        }
        
        #if DEBUG
        if UserDefaults.standard.bool(forKey: "debugParser") && content.contains("{") {
            print("[ThinkParser] 🔍 Result: PLAIN (JSON present but not a report)")
        }
        #endif

        guard let data = content.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode(ToolCall.self, from: data)
    }

    private static func isResearchReport(_ content: String) -> Bool {
        // v9.9.8: RED FIX - Strict Validation
        
        // 1. REJECT if extremely short (gravings, greetings, or broken fragments)
        guard content.count >= 200 else { 
            #if DEBUG
            if UserDefaults.standard.bool(forKey: "debugParser") {
                print("🚫 [ThinkParser] Rejected: Too short (\(content.count) chars)")
            }
            #endif
            return false 
        }
        
        // 2. REJECT if contains obvious greeting words
        let greetings = ["merhaba", "selam", "nasılsın", "hello", "hi there"]
        let lowerContent = content.lowercased()
        for greeting in greetings {
            if lowerContent.contains(greeting) && content.count < 1000 {
                #if DEBUG
                print("🚫 [ThinkParser] Rejected: Greeting detected in short-ish JSON")
                #endif
                return false
            }
        }
        
        // 3. REQUIRE minimum research depth and valid JSON
        guard let data = content.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return false
        }
        
        // Check mandatory fields
        let report = json["report"] as? [String: Any]
        let rec = json["recommendation"] as? [String: Any]
        
        // MUST have analyzed at least 1 source
        let sourcesCount = report?["sourcesAnalyzed"] as? Int ?? 0
        guard sourcesCount >= 1 else {
            #if DEBUG
            print("🚫 [ThinkParser] Rejected: No sources analyzed")
            #endif
            return false
        }
        
        // MUST have meaningful recommendation reasoning
        let reasoning = rec?["reasoning"] as? String ?? ""
        guard reasoning.count >= 50 else {
            #if DEBUG
            print("🚫 [ThinkParser] Rejected: Weak reasoning (\(reasoning.count) chars)")
            #endif
            return false
        }
        
        #if DEBUG
        print("✅ [ThinkParser] Valid research report")
        #endif
        return true
    }
}
