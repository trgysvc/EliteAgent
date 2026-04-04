// EliteAgent Ollama Bridge Manager - v7.9.0
import Foundation

/// Manages dynamic discovery and interaction with a local Ollama instance.
public actor OllamaManager {
    public static let shared = OllamaManager()
    
    private let baseURL = URL(string: "http://localhost:11434")!
    
    private init() {}
    
    /// Checks if the Ollama service is reachable on localhost.
    public func isConnected() async -> Bool {
        var request = URLRequest(url: baseURL)
        request.httpMethod = "HEAD"
        request.timeoutInterval = 1.0
        
        do {
            let (_, response) = try await URLSession.shared.data(for: request)
            return (response as? HTTPURLResponse)?.statusCode == 200
        } catch {
            return false
        }
    }
    
    /// Fetches the list of locally installed models from Ollama.
    public func fetchModels() async -> [ModelSource] {
        let tagsURL = baseURL.appendingPathComponent("/api/tags")
        var request = URLRequest(url: tagsURL)
        request.timeoutInterval = 2.0
        
        do {
            let (data, _) = try await URLSession.shared.data(for: request)
            let response = try JSONDecoder().decode(OllamaTagsResponse.self, from: data)
            
            return response.models.map { model in
                // v7.9.0: Map to bridge case for unified model handling
                .bridge(id: model.name, name: model.name)
            }
        } catch {
            print("[Ollama] Model fetch failed: \(error.localizedDescription)")
            return []
        }
    }
}

// MARK: - Decodable Helpers

struct OllamaTagsResponse: Codable {
    let models: [OllamaModel]
}

struct OllamaModel: Codable {
    let name: String
    let model: String
    let size: Int64
    let digest: String
    struct Details: Codable {
        let parent_model: String?
        let format: String
        let family: String
        let families: [String]?
        let parameter_size: String
        let quantization_level: String
    }
    let details: Details
}
