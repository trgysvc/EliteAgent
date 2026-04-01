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
    case missingApiKey
    
    public var description: String {
        switch self {
        case .invalidQuery: return "Invalid url query encoding."
        case .networkTimeout: return "The web search timed out (10s rigid limit)."
        case .parseFailed: return "Failed to parse Brave URLSession response."
        case .missingApiKey: return "Missing BRAVE_API_KEY in VaultManager. Please add it to Settings."
        }
    }
}

public struct WebSearchTool: Sendable {
    public init() {}
    
    public func search(query: String) async throws -> [WebSearchResult] {
        guard let encoded = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              let url = URL(string: "https://api.search.brave.com/res/v1/web/search?q=\(encoded)&count=5") else {
            throw WebSearchError.invalidQuery
        }
        
        let defaultVaultPath = PathConfiguration.shared.vaultURL
        guard let vault = try? VaultManager(configURL: defaultVaultPath),
              let apiKey = try? await vault.readSecret(for: "BRAVE_API_KEY"), !apiKey.isEmpty else {
            throw WebSearchError.missingApiKey
        }
        
        var request = URLRequest(url: url)
        request.setValue(apiKey, forHTTPHeaderField: "X-Subscription-Token")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.timeoutInterval = 10.0
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpRes = response as? HTTPURLResponse, httpRes.statusCode == 200 else {
            throw WebSearchError.networkTimeout
        }
        
        struct BraveResponse: Codable {
            struct WebCollection: Codable {
                let results: [BraveResult]?
            }
            struct BraveResult: Codable {
                let title: String?
                let url: String?
                let description: String?
            }
            let web: WebCollection?
        }
        
        let decoder = JSONDecoder()
        guard let braveObj = try? decoder.decode(BraveResponse.self, from: data),
              let results = braveObj.web?.results else {
            throw WebSearchError.parseFailed
        }
        
        let finalResults: [WebSearchResult] = results.compactMap {
            guard let url = $0.url, let text = $0.title, let result = $0.description else { return nil }
            return WebSearchResult(url: url, title: text, snippet: result)
        }
        
        return finalResults
    }
}
