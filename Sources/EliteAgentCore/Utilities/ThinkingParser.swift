import Foundation

public struct ThinkingResult: Sendable {
    public let thinking: String?
    public let finalAnswer: String
}

public final class ThinkingParser {
    public static func parse(_ text: String) -> ThinkingResult {
        let thinkPattern = "<think>([\\s\\S]*?)</think>"
        let finalPattern = "<final>([\\s\\S]*?)</final>"
        
        let thinkRegex = try? NSRegularExpression(pattern: thinkPattern, options: [])
        let finalRegex = try? NSRegularExpression(pattern: finalPattern, options: [])
        
        let nsString = text as NSString
        let range = NSRange(location: 0, length: nsString.length)
        
        var thinking: String?
        if let match = thinkRegex?.firstMatch(in: text, options: [], range: range) {
            thinking = nsString.substring(with: match.range(at: 1)).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        
        var finalAnswer = text
        if let match = finalRegex?.firstMatch(in: text, options: [], range: range) {
            finalAnswer = nsString.substring(with: match.range(at: 1)).trimmingCharacters(in: .whitespacesAndNewlines)
        } else if let thinkMatch = thinkRegex?.firstMatch(in: text, options: [], range: range) {
            // Fallback: If <final> is missing, take everything after </think>
            let endOfThink = thinkMatch.range.location + thinkMatch.range.length
            if endOfThink < nsString.length {
                finalAnswer = nsString.substring(from: endOfThink).trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }
        
        return ThinkingResult(thinking: thinking, finalAnswer: finalAnswer)
    }
}
