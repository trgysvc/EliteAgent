import Foundation

public actor BridgeProvider: LLMProvider {
    public nonisolated let providerID: ProviderID
    public nonisolated let providerType: ProviderType = .bridge
    public let capabilities: Set<Capability> = [.general, .code, .fast]
    public let costPer1KTokens: Decimal = 0
    public let maxContextTokens: Int = 32768
    public private(set) var status: ProviderStatus = .ready
    
    private let vaultManager: VaultManager
    private let endpointURL: URL
    public let modelName: String
    private let providerConf: ProviderConfig
    
    public init(providerID: ProviderID, vaultManager: VaultManager) throws {
        self.providerID = providerID
        self.vaultManager = vaultManager
        
        let config = vaultManager.config
        guard let conf = config.providers.first(where: { $0.id == providerID.rawValue }) else {
            throw ProviderError.networkError("Provider config not found for \(providerID.rawValue)")
        }
        self.providerConf = conf
        
        // Default to Ollama if not specified
        var urlStr = conf.endpoint ?? "http://localhost:11434/v1"
        if !urlStr.hasSuffix("/chat/completions") {
            urlStr = urlStr.hasSuffix("/") ? urlStr + "chat/completions" : urlStr + "/chat/completions"
        }
        self.endpointURL = URL(string: urlStr)!
        self.modelName = conf.modelName ?? "llama3.2:3b"
    }
    
    public func healthCheck() async -> Bool {
        do {
            try await preFlightCheck()
            return true
        } catch {
            return false
        }
    }
    
    /// Verifies if the model is loaded in the local provider (Ollama/LM Studio).
    /// If not loaded, it would ideally trigger a pull or run, but for now we verify existence.
    private func preFlightCheck() async throws {
        // Base URL for metadata (removing /v1/chat/completions)
        let baseURL = endpointURL.deletingLastPathComponent().deletingLastPathComponent()
        
        // Try Ollama Style (/api/tags)
        if baseURL.port == 11434 {
            let tagsURL = baseURL.appendingPathComponent("api/tags")
            let (data, response) = try await URLSession.shared.data(from: tagsURL)
            guard (response as? HTTPURLResponse)?.statusCode == 200 else {
                throw ProviderError.networkError("Ollama health check failed")
            }
            
            struct OllamaTags: Codable {
                struct Model: Codable { let name: String }
                let models: [Model]
            }
            
            let decoded = try JSONDecoder().decode(OllamaTags.self, from: data)
            if !decoded.models.contains(where: { $0.name == modelName || $0.name.hasPrefix(modelName + ":") }) {
                print("[BridgeProvider] Model \(modelName) not found in Ollama tags.")
                // In a future update, we could trigger 'ollama run' here.
            }
        } else {
            // Try OpenAI Style (/v1/models)
            let modelsURL = baseURL.appendingPathComponent("v1/models")
            let (data, response) = try await URLSession.shared.data(from: modelsURL)
            guard (response as? HTTPURLResponse)?.statusCode == 200 else {
                throw ProviderError.networkError("LM Studio health check failed")
            }
            
            struct OpenAIModels: Codable {
                struct Model: Codable { let id: String }
                let data: [Model]
            }
            
            let decoded = try JSONDecoder().decode(OpenAIModels.self, from: data)
            if !decoded.data.contains(where: { $0.id == modelName }) {
                print("[BridgeProvider] Model \(modelName) not found in LM Studio models.")
            }
        }
    }
    
    public func complete(_ request: CompletionRequest, useSafeMode: Bool) async throws -> CompletionResponse {
        // 1. Pre-flight check
        try await preFlightCheck()
        
        // 2. Prepare request
        var urlRequest = URLRequest(url: endpointURL)
        urlRequest.httpMethod = "POST"
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        var openAIMessages: [[String: Any]] = [
            ["role": "system", "content": request.systemPrompt]
        ]
        
        for msg in request.messages {
            openAIMessages.append(["role": msg.role, "content": msg.content])
        }
        
        let body: [String: Any] = [
            "model": modelName,
            "messages": openAIMessages,
            "max_tokens": request.maxTokens,
            "temperature": useSafeMode ? 0.0 : (request.temperature ?? 0.7)
        ]
        
        urlRequest.httpBody = try JSONSerialization.data(withJSONObject: body)
        urlRequest.timeoutInterval = 60.0
        
        let startTime = Date()
        let (data, response) = try await URLSession.shared.data(for: urlRequest)
        let latency = Int(Date().timeIntervalSince(startTime) * 1000)
        
        guard let httpRes = response as? HTTPURLResponse, httpRes.statusCode == 200 else {
            let errStr = String(data: data, encoding: .utf8) ?? "Unknown Error"
            throw ProviderError.networkError("HTTP \((response as? HTTPURLResponse)?.statusCode ?? 0): \(errStr)")
        }
        
        struct BridgeResponse: Codable {
            struct Choice: Codable {
                struct Message: Codable {
                    let role: String
                    let content: String?
                }
                let message: Message
            }
            struct Usage: Codable {
                let prompt_tokens: Int?
                let completion_tokens: Int?
                let total_tokens: Int?
            }
            let choices: [Choice]
            let usage: Usage?
        }
        
        let decoded = try JSONDecoder().decode(BridgeResponse.self, from: data)
        let text = decoded.choices.first?.message.content ?? ""
        
        let count = TokenCount(
            prompt: decoded.usage?.prompt_tokens ?? 0,
            completion: decoded.usage?.completion_tokens ?? 0,
            total: decoded.usage?.total_tokens ?? 0
        )
        
        // Bridge mode has 0 cost as it's local
        return CompletionResponse(
            taskID: request.taskID,
            providerUsed: providerID,
            content: text,
            tokensUsed: count,
            latencyMs: latency,
            costUSD: 0
        )
    }
}
