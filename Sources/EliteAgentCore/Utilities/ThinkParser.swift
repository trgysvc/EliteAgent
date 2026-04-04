import Foundation

public final class ThinkParser {
    public static func parse(_ text: String) -> [ThinkBlock] {
        var blocks: [ThinkBlock] = []
        
        let thinkPattern = "<think>([\\s\\S]*?)</think>"
        let finalPattern = "<final>([\\s\\S]*?)</final>"
        let toolPattern = "```tool_code([\\s\\S]*?)```" // Fixed: Standard backticks
        
        let thinkRegex = try? NSRegularExpression(pattern: thinkPattern, options: [])
        let finalRegex = try? NSRegularExpression(pattern: finalPattern, options: [])
        let toolRegex = try? NSRegularExpression(pattern: toolPattern, options: [])
        
        let nsString = text as NSString
        let range = NSRange(location: 0, length: nsString.length)
        
        let thinkMatches = thinkRegex?.matches(in: text, options: [], range: range) ?? []
        let finalMatches = finalRegex?.matches(in: text, options: [], range: range) ?? []
        let toolMatches = toolRegex?.matches(in: text, options: [], range: range) ?? []
        
        // 1. Common Path: Tags exist
        if !finalMatches.isEmpty || !thinkMatches.isEmpty || !toolMatches.isEmpty {
            // Find all unique thinking segments
            for thinkMatch in thinkMatches {
                let thought = nsString.substring(with: thinkMatch.range(at: 1)).trimmingCharacters(in: .whitespacesAndNewlines)
                blocks.append(ThinkBlock(thought: thought, toolCall: nil))
            }
            
            for toolMatch in toolMatches {
                let toolContent = sanitizeJSON(nsString.substring(with: toolMatch.range(at: 1)))
                if let data = toolContent.data(using: .utf8),
                   let toolCall = try? JSONDecoder().decode(ToolCall.self, from: data) {
                    blocks.append(ThinkBlock(thought: "", toolCall: toolCall))
                }
            }
            
            // Append Final Answers if present (treated as high-level thought if not tool)
            for finalMatch in finalMatches {
                let content = nsString.substring(with: finalMatch.range(at: 1)).trimmingCharacters(in: .whitespacesAndNewlines)
                blocks.append(ThinkBlock(thought: content, toolCall: nil))
            }
        }
        
        // 2. Failsafe: No tags, check for naked JSON ToolCall
        if blocks.isEmpty {
            let rawContent = sanitizeJSON(text)
            if let data = rawContent.data(using: .utf8),
               let toolCall = try? JSONDecoder().decode(ToolCall.self, from: data) {
                blocks.append(ThinkBlock(thought: "", toolCall: toolCall))
            } else if !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                // It's just plain text, treat as final thought
                blocks.append(ThinkBlock(thought: text, toolCall: nil))
            }
        }
        
        return blocks
    }

    /// Removes Markdown code block wrappers and other artifacts
    private static func sanitizeJSON(_ input: String) -> String {
        var clean = input.trimmingCharacters(in: .whitespacesAndNewlines)
        if clean.hasPrefix("```json") {
            clean = String(clean.dropFirst(7))
        } else if clean.hasPrefix("```") {
            clean = String(clean.dropFirst(3))
        }
        
        if clean.hasSuffix("```") {
            clean = String(clean.dropLast(3))
        }
        
        return clean.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
