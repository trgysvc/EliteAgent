import Foundation

public final class ThinkParser {
    public static func parse(_ text: String) -> [ThinkBlock] {
        var blocks: [ThinkBlock] = []
        
        // v9.9: Patterns tracking
        let thinkPattern = "<think>([\\s\\S]*?)</think>"
        let finalPattern = "<final>([\\s\\S]*?)</final>"
        let toolPattern = "```tool_code([\\s\\S]*?)(?:```|$)"
        
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
        
        for toolMatch in toolMatches {
            let toolContent = extractJSONrobustly(nsString.substring(with: toolMatch.range(at: 1)))
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
        
        // 2. Failsafe: Fuzzy Matcher for plain text (media_control, messenger, etc)
        if blocks.filter({ $0.toolCall != nil }).isEmpty {
            if let fuzzyTool = performFuzzyMatch(text) {
                #if DEBUG
                print("[ThinkParser] 🔍 Fuzzy matched: \(fuzzyTool.tool)")
                #endif
                blocks.append(ThinkBlock(thought: "", toolCall: fuzzyTool))
            }
        }
        
        // 3. Last Resort: Robust JSON extraction on full text
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
        // v9.9: Special handling for Premium Research Reports
        // If content contains "report" and "recommendation", it's likely a final answer JSON.
        // We handle it as a thought block so the UI can parse and render it as a report.
        if content.contains("\"report\":") && content.contains("\"recommendation\":") {
            return nil 
        }
        
        guard let data = content.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode(ToolCall.self, from: data)
    }

    private static func performFuzzyMatch(_ text: String) -> ToolCall? {
        let lower = text.lowercased()
        
        // Fuzzy 1: Media Control
        if lower.contains("media_control") {
            let hasAction = lower.contains(any: ["play", "open", "aç", "başlat", "oynat", "çal"])
            if hasAction {
                if let target = extractQuotedContent(from: text) {
                    return ToolCall(tool: "media_control", params: ["action": AnyCodable("play_content"), "searchTerm": AnyCodable(target)])
                }
            }
        }
        
        // Fuzzy 2: Messenger
        if lower.contains("messenger") || lower.contains("whatsapp") {
            if lower.contains(any: ["send", "gönder", "yaz", "mesaj"]) {
                if let msg = extractQuotedContent(from: text) {
                    return ToolCall(tool: "messenger", params: ["platform": AnyCodable("whatsapp"), "recipient": AnyCodable(""), "message": AnyCodable(msg)])
                }
            }
        }
        
        return nil
    }

    private static func extractQuotedContent(from text: String) -> String? {
        let regex = try? NSRegularExpression(pattern: "\"([^\"]+)\"")
        let nsText = text as NSString
        if let match = regex?.firstMatch(in: text, options: [], range: NSRange(location: 0, length: nsText.length)) {
            return nsText.substring(with: match.range(at: 1))
        }
        return nil
    }
}

fileprivate extension String {
    func contains(any substrings: [String]) -> Bool {
        for s in substrings { if self.contains(s) { return true } }
        return false
    }
}
