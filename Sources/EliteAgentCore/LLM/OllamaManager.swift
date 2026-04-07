// EliteAgent Ollama Bridge Manager - v7.9.0
import Foundation
import Network

/// Manages dynamic discovery and interaction with a local Ollama instance.
public actor OllamaManager {
    public static let shared = OllamaManager()
    
    private let baseURL = URL(string: "http://localhost:11434")!
    private var lastFailure: Date = .distantPast
    private let discoveryCooldown: TimeInterval = 300 // 5 minutes
    
    private init() {}
    
    /// Dynamic Reachability Check - v9.9.2
    /// Returns true ONLY if the Ollama service is actually listening on localhost.
    /// This prevents URLSession from spamming 'Connection refused' to the Xcode console.
    public func canConnect() async -> Bool {
        // v10.4: Discovery Lock - Silent skip if we failed recently
        let now = Date()
        if now.timeIntervalSince(lastFailure) < discoveryCooldown {
            AgentLogger.logAudit(level: .info, agent: "Ollama", message: "Discovery skipped (cooldown active). Next check in \(Int(discoveryCooldown - now.timeIntervalSince(lastFailure)))s")
            return false
        }
        
        let host = NWEndpoint.Host("127.0.0.1")
        let port = NWEndpoint.Port(integerLiteral: 11434)
        
        // v10.5: Use .quiet to prevent system log pollution if possible, 
        // but since NWConnection is inherently noisy, we just enforce a strict lock.
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
        
        let success = await withCheckedContinuation { continuation in
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
            
            // v10.5: Ultra-short timeout (200ms) for local loopback
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                if state.tryRespond() {
                    connection.cancel()
                    continuation.resume(returning: false)
                }
            }
            
            connection.start(queue: .global())
        }
        
        if !success {
            self.markFailure()
        }
        return success
    }
    
    private func markFailure() {
        self.lastFailure = Date()
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
        } catch let err {
            // v10.5.5: Full Transparency - Log Failure
            AgentLogger.logAudit(level: .warn, agent: "Ollama", message: "Model fetch failed: \(err.localizedDescription)")            // v10.5.6: Lower noise - Ollama is optional for this user
            print("🔍 [DEBUG] Ollama is not active on 11434 (Connection Refused). Use MLX/Titan for local inference.")
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
