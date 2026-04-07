// EliteAgent Ollama Bridge Manager - v7.9.0
import Foundation
import Network

/// Manages dynamic discovery and interaction with a local Ollama instance.
public actor OllamaManager {
    public static let shared = OllamaManager()
    
    private let baseURL = URL(string: "http://localhost:11434")!
    
    private init() {}
    
    /// Dynamic Reachability Check - v9.9.2
    /// Returns true ONLY if the Ollama service is actually listening on localhost.
    /// This prevents URLSession from spamming 'Connection refused' to the Xcode console.
    public func canConnect() async -> Bool {
        let host = NWEndpoint.Host("127.0.0.1")
        let port = NWEndpoint.Port(integerLiteral: 11434)
        let connection = NWConnection(host: host, port: port, using: .tcp)
        
        class ResponseState: @unchecked Sendable { 
            var hasResponded = false 
            let lock = NSLock()
            func tryRespond() -> Bool {
                lock.lock(); defer { lock.unlock() }
                if hasResponded { return false }
                hasResponded = true
                return true
            }
        }
        let state = ResponseState()
        
        return await withCheckedContinuation { continuation in
            connection.stateUpdateHandler = { newState in
                switch newState {
                case .ready:
                    if state.tryRespond() {
                        connection.cancel()
                        continuation.resume(returning: true)
                    }
                case .failed, .cancelled:
                    if state.tryRespond() {
                        continuation.resume(returning: false)
                    }
                default: break
                }
            }
            
            // Timeout to prevent hanging
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                if state.tryRespond() {
                    connection.cancel()
                    continuation.resume(returning: false)
                }
            }
            
            connection.start(queue: .global())
        }
    }
    
    /// Fetches the list of locally installed models from Ollama.
    public func fetchModels() async -> [ModelSource] {
        // v9.9.2: Silence console spam check
        guard await canConnect() else { return [] }
        
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
            // Only log if connection was supposedly successful but fetch failed
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
