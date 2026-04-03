import Foundation

public final class ThinkParser {
    public static func parse(_ text: String) -> [ThinkBlock] {
        var blocks: [ThinkBlock] = []
        
        let thinkPattern = "<think>([\\s\\S]*?)</think>"
        let finalPattern = "<final>([\\s\\S]*?)</final>"
        
        let thinkRegex = try? NSRegularExpression(pattern: thinkPattern, options: [])
        let finalRegex = try? NSRegularExpression(pattern: finalPattern, options: [])
        
        let nsString = text as NSString
        let range = NSRange(location: 0, length: nsString.length)
        
        // Find all think blocks
        let thinkMatches = thinkRegex?.matches(in: text, options: [], range: range) ?? []
        let finalMatches = finalRegex?.matches(in: text, options: [], range: range) ?? []
        
        // If we have at least one final block, we pair it with the preceding think block (if any)
        if !finalMatches.isEmpty {
            for finalMatch in finalMatches {
                let finalContent = nsString.substring(with: finalMatch.range(at: 1)).trimmingCharacters(in: .whitespacesAndNewlines)
                
                // Find the think block that ends before this final block starts
                var associatedThought = ""
                if let lastThink = thinkMatches.last(where: { $0.range.location + $0.range.length <= finalMatch.range.location }) {
                    associatedThought = nsString.substring(with: lastThink.range(at: 1)).trimmingCharacters(in: .whitespacesAndNewlines)
                } else if !thinkMatches.isEmpty {
                    // Just take the first one if it doesn't strictly precede (less likely but possible)
                    associatedThought = nsString.substring(with: thinkMatches[0].range(at: 1)).trimmingCharacters(in: .whitespacesAndNewlines)
                }
                
                // Try to parse finalContent as a ToolCall JSON
                if let data = finalContent.data(using: .utf8),
                   let toolCall = try? JSONDecoder().decode(ToolCall.self, from: data) {
                    blocks.append(ThinkBlock(thought: associatedThought, toolCall: toolCall))
                } else {
                    // Not a tool call, treat as final answer
                    // Note: OrchestratorRuntime uses block.thought for the final answer if toolCall is nil
                    blocks.append(ThinkBlock(thought: finalContent, toolCall: nil))
                }
            }
        }
        
        return blocks
    }
}
