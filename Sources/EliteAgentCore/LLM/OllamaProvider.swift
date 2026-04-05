import Foundation

/// Handles Ollama (Bridge) provider setup during first-run.
@MainActor
public final class OllamaProvider {
    public static let shared = OllamaProvider()
    
    private init() {}
    
    /// Check if Ollama is installed and running by testing the API endpoint.
    public func isOllamaRunning() async -> Bool {
        let url = URL(string: "http://localhost:11434/api/tags")!
        let request = URLRequest(url: url)
        
        do {
            let (_, response) = try await URLSession.shared.data(for: request)
            if let http = response as? HTTPURLResponse {
                return http.statusCode == 200
            }
        } catch {
            return false
        }
        return false
    }
    
    /// Fetch available models from Ollama.
    public func fetchOllamaModels() async throws -> [String] {
        let url = URL(string: "http://localhost:11434/api/tags")!
        let (data, _) = try await URLSession.shared.data(from: url)
        
        struct OllamaTags: Codable {
            struct Model: Codable { let name: String }
            let models: [Model]
        }
        
        let decoder = JSONDecoder()
        let tags = try decoder.decode(OllamaTags.self, from: data)
        return tags.models.map { $0.name }
    }
}
