import Foundation
import MLX
import MLXLLM

/// v31.3: Official v3-Native MLX Provider
/// Bridges the generic Completion API to the hardware-accelerated InferenceActor.
public actor MLXProvider: LocalLLMProvider {
    public static let shared = MLXProvider(providerID: .mlx)
    
    public nonisolated let providerID: ProviderID
    public nonisolated let providerType: ProviderType = .local
    public let capabilities: Set<Capability> = [.think, .code, .general]
    public let costPer1KTokens: Decimal = 0
    public let maxContextTokens: Int = 16384
    public private(set) var status: ProviderStatus = .ready
    
    public nonisolated var isLoaded: Bool { true }
    
    public init(providerID: ProviderID) {
        self.providerID = providerID
        self.status = .ready
    }
    
    public func healthCheck() async -> Bool {
        return await InferenceActor.shared.isModelLoaded
    }
    
    public func loadModel(_ modelName: String) async throws {
        self.status = .loading
        do {
            let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            let modelURL = appSupport.appendingPathComponent("EliteAgent/Models/\(modelName)")
            
            self.status = .priming
            try await InferenceActor.shared.loadModel(at: modelURL)
            self.status = .ready
        } catch {
            self.status = .error
            throw error
        }
    }
    
    public func unloadModel() async {
        await InferenceActor.shared.unloadModel()
        self.status = .idle
    }
    
    public func complete(_ request: CompletionRequest, useSafeMode: Bool) async throws -> CompletionResponse {
        let startTime = Date()
        let messages = request.messages.map { Message(role: $0.role, content: $0.content) }
        
        // v3-Native Stream Handling
        let stream = try await InferenceActor.shared.generate(
            messages: messages,
            systemPrompt: request.systemPrompt,
            maxTokens: request.maxTokens
        )
        
        var fullContent = ""
        var firstTokenTime: Date?
        var finalMetrics: (prompt: Int, completion: Int, tps: Double)?
        
        for await chunk in stream {
            switch chunk {
            case .token(let text):
                if firstTokenTime == nil {
                    firstTokenTime = Date()
                }
                fullContent += text
            case .metrics(let prompt, let completion, let tps):
                finalMetrics = (prompt, completion, tps)
            case .tool(let call):
                AgentLogger.logInfo("🛠 [MLX-Provider] Tool indicated: \(call)")
            }
        }
        
        if fullContent.isEmpty {
            throw ProviderError.emptyResponse
        }
        
        let latency = Int(Date().timeIntervalSince(startTime) * 1000)
        let count = TokenCount(
            prompt: finalMetrics?.prompt ?? (messages.map { $0.content.count }.reduce(0, +) / 4),
            completion: finalMetrics?.completion ?? (fullContent.count / 4),
            total: (finalMetrics?.prompt ?? 0) + (finalMetrics?.completion ?? 0)
        )
        
        return CompletionResponse(
            taskID: request.taskID,
            providerUsed: providerID,
            content: fullContent,
            tokensUsed: count,
            latencyMs: latency,
            costUSD: 0
        )
    }
}
