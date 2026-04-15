import Foundation

/// v23.0: Tiered Context Philosophy - Every tool execution results in an EliteObservation.
/// This allows for L2 (Fact-based) summarization and L3 (Archival) sync.
public protocol EliteObservation: Sendable {
    var timestamp: Date { get }
    var source: String { get }
    var summary: String { get }
    
    /// Returns the semantic 'Fact' string to be injected into L2 (Warm) context.
    func toFactString() -> String
}

extension EliteObservation {
    public func toFactString() -> String {
        let df = RelativeDateTimeFormatter()
        let timeStr = df.localizedString(for: timestamp, relativeTo: Date())
        return "Fact (\(source) - \(timeStr)): \(summary)"
    }
}

/// v23.0: Standard implementation for raw tool results.
public struct BasicObservation: EliteObservation {
    public let timestamp: Date
    public let source: String
    public let summary: String
    
    public init(source: String, summary: String, timestamp: Date = Date()) {
        self.source = source
        self.summary = summary
        self.timestamp = timestamp
    }
    
    public static func from(rawResult: String, toolName: String) -> BasicObservation {
        // v23.0: Smart Extraction - Clean up the raw result for the summary.
        let cleaned = rawResult
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "\\[.*_WIDGET\\].*", with: "[Visual Widget Attached]", options: .regularExpression)
        
        let truncated = cleaned.count > 150 ? String(cleaned.prefix(147)) + "..." : cleaned
        return BasicObservation(source: toolName, summary: truncated)
    }
}

/// v23.0: Specialization for Research/Web tasks to enforce Citation and Grounding.
public struct ResearchObservation: EliteObservation {
    public let timestamp: Date = Date()
    public let source: String = "Research Engine"
    public let summary: String
    public let urls: [String]
    
    public init(summary: String, urls: [String]) {
        self.summary = summary
        self.urls = urls
    }
    
    public func toFactString() -> String {
        let citation = urls.isEmpty ? "[No URLs found]" : urls.joined(separator: ", ")
        return "Research Fact: \(summary). Sources: \(citation)"
    }
}
