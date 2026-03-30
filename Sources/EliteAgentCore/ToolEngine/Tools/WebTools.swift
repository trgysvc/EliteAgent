import Foundation

/// WebSearchToolWrapper: DuckDuckGo tabanlı web aramalarını AgentTool protokolüne bağlar.
public struct WebSearchToolWrapper: AgentTool {
    public let name = "web_search"
    public let description = "Mevcut bilgilerle yanıtlanamayan sorular için internette arama yapar. Parametre: query (arama metni)."
    private let engine = WebSearchTool()
    
    public init() {}
    
    public func execute(params: [String: AnyCodable], session: Session) async throws -> String {
        guard let query = params["query"]?.value as? String else {
            throw ToolError.missingParameter("query")
        }
        
        let results = try await engine.search(query: query)
        let output = results.map { "[\($0.title)](\($0.url)): \($0.snippet)" }.joined(separator: "\n\n")
        return output.isEmpty ? "Sonuç bulunamadı." : output
    }
}

/// WebFetchToolWrapper: Belirli bir URL'nin içeriğini okur ve metne dönüştürür.
public struct WebFetchToolWrapper: AgentTool {
    public let name = "web_fetch"
    public let description = "Belirli bir web sayfasının içeriğini okur. Parametre: url (URL adresi)."
    private let engine = WebFetchTool()
    
    public init() {}
    
    public func execute(params: [String: AnyCodable], session: Session) async throws -> String {
        guard let url = params["url"]?.value as? String else {
            throw ToolError.missingParameter("url")
        }
        
        return try await engine.fetch(url: url)
    }
}
