import Foundation

// Mock classes/structs
struct AnyCodable: Codable {
    let value: Any
    init(_ value: Any) { self.value = value }
    func encode(to encoder: Encoder) throws {}
    init(from decoder: Decoder) throws { self.value = "" }
}

struct ToolCall: Codable {
    let tool: String
    let params: [String: AnyCodable]
}

struct ThinkBlock {
    let thought: String
    let toolCall: ToolCall?
}

class ThinkParser {
    static func parse(_ text: String) -> [ThinkBlock] {
        var blocks: [ThinkBlock] = []
        // v9.9.3: Improved regex to handle boundaries between multiple unwrapped blocks
        let toolPattern = "(?:```)?tool_code\\s*([\\s\\S]*?)(?=```|tool_code|$)"
        let toolRegex = try? NSRegularExpression(pattern: toolPattern, options: [])
        let nsString = text as NSString
        let range = NSRange(location: 0, length: nsString.length)
        let toolMatches = toolRegex?.matches(in: text, options: [], range: range) ?? []
        
        for toolMatch in toolMatches {
            let captured = nsString.substring(with: toolMatch.range(at: 1))
            let toolContent = extractJSONrobustly(captured)
            if let toolCall = tryParseToolCall(from: toolContent) {
                blocks.append(ThinkBlock(thought: "", toolCall: toolCall))
            }
        }
        return blocks
    }
    
    static func extractJSONrobustly(_ input: String) -> String {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        if let first = input.firstIndex(of: "{"), let last = input.lastIndex(of: "}") {
            return String(input[first...last])
        }
        return trimmed
    }
    
    static func tryParseToolCall(from content: String) -> ToolCall? {
        guard let data = content.data(using: .utf8) else { return nil }
        // Minimal mock decoder
        if let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let tool = dict["tool"] as? String {
            return ToolCall(tool: tool, params: [:])
        }
        return nil
    }
}

let testInput = """
<think>Düşünüyorum...</think>

tool_code {
  "tool": "media_control",
  "params": { "action": "pause" }
}

tool_code {
  "tool": "media_control",
  "params": { "action": "play_content", "searchTerm": "Coffee" }
}
"""

let results = ThinkParser.parse(testInput)
print("Parsed \(results.count) tools.")
for (i, r) in results.enumerated() {
    print("Tool \(i+1): \(r.toolCall?.tool ?? "nil")")
}

if results.count == 2 {
    print("✅ TEST PASSED: Successfully extracted multiple tools without backticks.")
} else {
    print("❌ TEST FAILED: Expected 2 tools, got \(results.count)")
}
