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
    case networkTimeout(String)
    case parseFailed(String)
    case missingApiKey(String)
    
    public var description: String {
        switch self {
        case .invalidQuery: return "Invalid url query encoding."
        case .networkTimeout(let svc): return "\(svc) web search timed out."
        case .parseFailed(let svc): return "Failed to parse \(svc) response."
        case .missingApiKey(let svc): return "Missing \(svc) API Key in Settings."
        }
    }
}

public struct WebSearchTool: Sendable {
    public init() {}
    
    public func search(query: String) async throws -> [WebSearchResult] {
        // Try Serper first if available (Google Results)
        if let serperResults = try? await searchSerper(query: query) {
            return serperResults
        }
        
        // Fallback to Brave
        do {
            return try await searchBrave(query: query)
        } catch {
            // Final fallback: Let orchestrator know we failed both API paths
            throw error
        }
    }

    private func searchSerper(query: String) async throws -> [WebSearchResult] {
        guard let _ = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              let url = URL(string: "https://google.serper.dev/search") else {
            throw WebSearchError.invalidQuery
        }

        let vaultPath = PathConfiguration.shared.vaultURL
        guard let vault = try? VaultManager(configURL: vaultPath),
              let apiKey = try? await vault.readSecret(for: "SERPER_API_KEY"), !apiKey.isEmpty else {
            throw WebSearchError.missingApiKey("Serper")
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue(apiKey, forHTTPHeaderField: "X-API-KEY")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let body = ["q": query, "num": 10] as [String : Any]
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)
        request.timeoutInterval = 15.0

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpRes = response as? HTTPURLResponse, httpRes.statusCode == 200 else {
            throw WebSearchError.networkTimeout("Serper")
        }

        struct SerperResponse: Codable {
            struct SResult: Codable {
                let title: String?
                let link: String?
                let snippet: String?
            }
            let organic: [SResult]?
        }

        let decoder = JSONDecoder()
        guard let serperObj = try? decoder.decode(SerperResponse.self, from: data),
              let organic = serperObj.organic else {
            throw WebSearchError.parseFailed("Serper")
        }

        return organic.compactMap {
            guard let url = $0.link, let title = $0.title, let snippet = $0.snippet else { return nil }
            return WebSearchResult(url: url, title: title, snippet: snippet)
        }
    }
    
    private func searchBrave(query: String) async throws -> [WebSearchResult] {
        guard let encoded = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              let url = URL(string: "https://api.search.brave.com/res/v1/web/search?q=\(encoded)&count=10") else {
            throw WebSearchError.invalidQuery
        }
        
        let vaultPath = PathConfiguration.shared.vaultURL
        guard let vault = try? VaultManager(configURL: vaultPath),
              let apiKey = try? await vault.readSecret(for: "BRAVE_API_KEY"), !apiKey.isEmpty else {
            throw WebSearchError.missingApiKey("Brave")
        }
        
        var request = URLRequest(url: url)
        request.setValue(apiKey, forHTTPHeaderField: "X-Subscription-Token")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.timeoutInterval = 15.0
        
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpRes = response as? HTTPURLResponse, httpRes.statusCode == 200 else {
            throw WebSearchError.networkTimeout("Brave")
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
            throw WebSearchError.parseFailed("Brave")
        }
        
        return results.compactMap {
            guard let url = $0.url, let text = $0.title, let result = $0.description else { return nil }
            return WebSearchResult(url: url, title: text, snippet: result)
        }
    }
}
