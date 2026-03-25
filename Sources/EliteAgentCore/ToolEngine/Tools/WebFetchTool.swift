import Foundation

public struct WebFetchTool: Sendable {
    public init() {}
    
    public func fetch(url: String, timeoutMs: Int = 10000) async throws -> String {
        guard let fetchURL = URL(string: url) else {
            throw URLError(.badURL)
        }
        
        var request = URLRequest(url: fetchURL)
        request.timeoutInterval = TimeInterval(timeoutMs) / 1000.0
        
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse, (200...299).contains(httpResponse.statusCode) else {
            throw URLError(.badServerResponse)
        }
        
        guard let htmlString = String(data: data, encoding: .utf8) else {
            throw URLError(.cannotDecodeRawData)
        }
        
        // Strip out script and style tags completely
        let scriptRegex = try NSRegularExpression(pattern: "<script[^>]*>[\\s\\S]*?</script>", options: .caseInsensitive)
        var text = scriptRegex.stringByReplacingMatches(in: htmlString, range: NSRange(htmlString.startIndex..., in: htmlString), withTemplate: "")
        
        let styleRegex = try NSRegularExpression(pattern: "<style[^>]*>[\\s\\S]*?</style>", options: .caseInsensitive)
        text = styleRegex.stringByReplacingMatches(in: text, range: NSRange(text.startIndex..., in: text), withTemplate: "")
        
        // Strip remaining HTML tags
        let tagRegex = try NSRegularExpression(pattern: "<[^>]+>", options: .caseInsensitive)
        text = tagRegex.stringByReplacingMatches(in: text, range: NSRange(text.startIndex..., in: text), withTemplate: " ")
        
        // Collapse multiple spaces
        let spaceRegex = try NSRegularExpression(pattern: "\\s+", options: .caseInsensitive)
        let plainText = spaceRegex.stringByReplacingMatches(in: text, range: NSRange(text.startIndex..., in: text), withTemplate: " ").trimmingCharacters(in: .whitespacesAndNewlines)
        
        // Truncate to a reasonable limit (e.g. 100.000 chars) to prevent context explosion
        return String(plainText.prefix(100_000))
    }
}
