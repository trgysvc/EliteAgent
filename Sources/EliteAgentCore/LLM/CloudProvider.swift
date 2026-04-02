import Foundation

public actor CloudProvider: LLMProvider {
    public nonisolated let providerID: ProviderID
    public nonisolated let providerType: ProviderType = .cloud
    public let capabilities: Set<Capability> = [.general, .code, .fast]
    public let costPer1KTokens: Decimal = 0.0001
    public let maxContextTokens: Int = 1000000
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
            throw ProviderError.networkError("Provider config not found in vault.plist")
        }
        self.providerConf = conf
        var urlStr = conf.endpoint ?? "https://openrouter.ai/api/v1"
        if !urlStr.hasSuffix("/chat/completions") && !urlStr.contains("/messages") {
            urlStr = urlStr.hasSuffix("/") ? urlStr + "chat/completions" : urlStr + "/chat/completions"
        }
        self.endpointURL = URL(string: urlStr)!
        self.modelName = conf.modelName ?? "google/gemini-3-flash-preview"
    }
    
    public func healthCheck() async -> Bool {
        return (try? await vaultManager.getAPIKey(for: providerConf)) != nil
    }
    
    public func complete(_ request: CompletionRequest) async throws -> CompletionResponse {
        let apiKey: String
        do {
            print("[TRACE] CloudProvider: Retrieving API Key...")
            apiKey = try await vaultManager.getAPIKey(for: providerConf)
            print("[TRACE] CloudProvider: API Key retrieved (length: \(apiKey.count)).")
        } catch {
            print("[TRACE] CloudProvider: API Key retrieval FAILED: \(error)")
            throw ProviderError.networkError("API Key retrieval failed: \(error)")
        }
        
        var urlRequest = URLRequest(url: endpointURL)
        urlRequest.httpMethod = "POST"
        urlRequest.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        urlRequest.setValue("https://eliteagent.app", forHTTPHeaderField: "HTTP-Referer")
        urlRequest.setValue("EliteAgent/5.2", forHTTPHeaderField: "X-Title")
        
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
            "temperature": request.temperature ?? 0.2
        ]
        
        urlRequest.httpBody = try JSONSerialization.data(withJSONObject: body)
        urlRequest.timeoutInterval = 60.0 // Strict 60s Timeout for Stability
        
        let startTime = Date()
        print("[TRACE] CloudProvider: Starting URLSession data task to \(endpointURL)...")
        
        let data: Data
        let response: URLResponse
        
        do {
            (data, response) = try await URLSession.shared.data(for: urlRequest)
        } catch let error as URLError where error.code == .timedOut {
            print("[TRACE] CloudProvider: URLSession TIMED OUT after 60s.")
            throw ProviderError.networkError("Network Timeout (60s limit reached)")
        } catch {
            throw error
        }
        
        let latency = Int(Date().timeIntervalSince(startTime) * 1000)
        print("[TRACE] CloudProvider: URLSession data task COMPLETED. Latency: \(latency)ms")
        
        guard let httpRes = response as? HTTPURLResponse else {
            throw ProviderError.networkError("Invalid HTTP response")
        }
        
        guard httpRes.statusCode == 200 else {
            let errStr = String(data: data, encoding: .utf8) ?? "Unknown HTTP Error"
            print("[CLOUD_PROVIDER ERROR] HTTP \(httpRes.statusCode): \(errStr)")
            throw ProviderError.networkError("Status \(httpRes.statusCode): \(errStr)")
        }
        
        struct OpenAIResponse: Codable {
            struct Choice: Codable {
                struct ChatMessage: Codable {
                    let role: String
                    let content: String?        // optional — can be null
                    let reasoning: String?      // optional — reasoning models
                    
                    struct ReasoningDetail: Codable {
                        let type: String
                        let text: String?
                    }
                    let reasoningDetails: [ReasoningDetail]?
                    
                    enum CodingKeys: String, CodingKey {
                        case role, content, reasoning
                        case reasoningDetails = "reasoning_details"
                    }
                    
                    // Computed property — returns best available text
                    var bestContent: String {
                        content ?? reasoning ?? 
                        reasoningDetails?.compactMap(\.text).first ?? ""
                    }
                }
                let message: ChatMessage
            }
            struct Usage: Codable {
                let prompt_tokens: Int?
                let completion_tokens: Int?
                let total_tokens: Int?
            }
            let choices: [Choice]
            let usage: Usage?
        }
        
        let decoded: OpenAIResponse
        do {
            decoded = try JSONDecoder().decode(OpenAIResponse.self, from: data)
        } catch {
            let rawData = String(data: data, encoding: .utf8) ?? "unable to decode raw string"
            print("[CLOUD_PROVIDER ERROR] Failed to decode JSON. Error: \(error)")
            print("[CLOUD_PROVIDER RAW RESP] \(rawData)")
            throw ProviderError.networkError("JSON parsing failed: \(error.localizedDescription)")
        }
        
        let message = decoded.choices.first?.message
        let text = message?.bestContent ?? ""
        
        guard !text.isEmpty else {
            let rawData = String(data: data, encoding: .utf8) ?? "none"
            print("[CLOUD_PROVIDER EMPTY TEXT] raw: \(rawData)")
            throw ProviderError.networkError("Failed to parse completion text (bestContent empty)")
        }
        
        let count = TokenCount(
            prompt: decoded.usage?.prompt_tokens ?? 0,
            completion: decoded.usage?.completion_tokens ?? 0,
            total: decoded.usage?.total_tokens ?? 0
        )
        
        // Dynamic Cost Calculation
        let promptPrice = Decimal(providerConf.promptPrice ?? 0)
        let completionPrice = Decimal(providerConf.completionPrice ?? 0)
        let cost = (Decimal(count.prompt) * promptPrice) + (Decimal(count.completion) * completionPrice)

        // Extract think block natively if model returned it inside <think> tags
        let parsed = LLMModel.parseThinkBlock(from: text)
        
        AgentLogger.logAudit(level: .info, agent: "CloudProvider", message: "LLM Call completed | Model: \(modelName) | Latency: \(latency)ms | Tokens: \(count.total)")
        
        return CompletionResponse(
            taskID: request.taskID,
            providerUsed: providerID,
            content: parsed.content,
            thinkBlock: parsed.think,
            tokensUsed: count,
            latencyMs: latency,
            costUSD: cost
        )
    }
}
