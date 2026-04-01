import Foundation
import MLX
import MLXLLM

/// Orchestration-layer provider that bridges the generic Completion API to the 
/// hardware-accelerated InferenceActor (Titan Engine).
public actor MLXProvider: LocalLLMProvider {
    public nonisolated let providerID: ProviderID
    public nonisolated let providerType: ProviderType = .local
    public let capabilities: Set<Capability> = [.think, .code, .general]
    public let costPer1KTokens: Decimal = 0
    public let maxContextTokens: Int = 16384 // Synchronized with InferenceActor
    public private(set) var status: ProviderStatus = .ready
    
    public init(providerID: ProviderID) {
        self.providerID = providerID
        self.status = .ready
    }
    
    public func healthCheck() async -> Bool {
        return true // InferenceActor manages its own health
    }
    
    public func loadModel(_ modelName: String) async throws {
        self.status = .loading
        do {
            let modelURL = getModelURL(for: modelName)
            try await InferenceActor.shared.loadModel(at: modelURL)
            self.status = .ready
        } catch {
            self.status = .error
            throw error
        }
    }
    
    private func getModelURL(for name: String) -> URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return appSupport.appendingPathComponent("EliteAgent/Models/\(name)")
    }
    
    public func complete(_ request: CompletionRequest) async throws -> CompletionResponse {
        let startTime = Date()
        
        // Single prompt construction - InferenceActor handles ChatML specialization
        // We take the last user message or join them.
        let prompt = request.messages.last?.content ?? ""
        
        // FIX: Added 'await' for actor-isolated method call
        let stream = await InferenceActor.shared.generate(prompt: prompt, maxTokens: request.maxTokens)
        var fullContent = ""
        
        for await chunk in stream {
            fullContent += chunk
        }
        
        let latency = Int(Date().timeIntervalSince(startTime) * 1000)
        
        // Estimates for local token counts (Simplified)
        let count = TokenCount(
            prompt: prompt.count / 4,
            completion: fullContent.count / 4,
            total: (prompt.count + fullContent.count) / 4
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
