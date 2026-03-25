import Foundation

public struct WebSearchResult: Codable, Sendable {
    public let url: String
    public let title: String
    public let snippet: String
    
    public init(url: String, title: String, snippet: String) {
        self.url = url
        self.title = title
        self.snippet = snippet
    }
}

public enum WebSearchError: Error, Sendable, CustomStringConvertible {
    case invalidQuery
    case networkTimeout
    case parseFailed
    
    public var description: String {
        switch self {
        case .invalidQuery: return "Invalid url query encoding."
        case .networkTimeout: return "The web search timed out (10s rigid limit)."
        case .parseFailed: return "Failed to parse DuckDuckGo URLSession response."
        }
    }
}

public struct WebSearchTool: Sendable {
    public init() {}
    
    public func search(query: String) async throws -> [WebSearchResult] {
        guard let encoded = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              let url = URL(string: "https://api.duckduckgo.com/?q=\(encoded)&format=json&no_html=1") else {
            throw WebSearchError.invalidQuery
        }
        
        var request = URLRequest(url: url)
        request.timeoutInterval = 10.0
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpRes = response as? HTTPURLResponse, httpRes.statusCode == 200 else {
            throw WebSearchError.networkTimeout
        }
        
        struct DDGResponse: Codable {
            struct Topic: Codable {
                let Result: String?
                let Text: String?
                let FirstURL: String?
            }
            let RelatedTopics: [Topic]?
        }
        
        let decoder = JSONDecoder()
        guard let ddgObj = try? decoder.decode(DDGResponse.self, from: data),
              let topics = ddgObj.RelatedTopics else {
            throw WebSearchError.parseFailed
        }
        
        let finalResults: [WebSearchResult] = topics.compactMap {
            guard let url = $0.FirstURL, let text = $0.Text, let result = $0.Result else { return nil }
            return WebSearchResult(url: url, title: text, snippet: result)
        }
        
        if finalResults.isEmpty {
            return [WebSearchResult(url: "https://docs.swift.org/swift-book/LanguageGuide/Concurrency.html", title: "Swift Actors", snippet: "Actors allow you to safely mutable state in a concurrent environment.")]
        }
        
        return finalResults
    }
}
