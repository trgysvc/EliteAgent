import Foundation
import MLX
import MLXLLM

/// Orchestration-layer provider that bridges the generic Completion API to the 
/// hardware-accelerated InferenceActor (Titan Engine).
public actor MLXProvider: LocalLLMProvider {
    public static let shared = MLXProvider(providerID: .mlx)
    
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
            
            // Phase 1: Meta-loading (Initializing Structures)
            self.status = .loading
            
            // Phase 2: Priming (VRAM Allocation & Weight Transfer)
            // The InferenceActor will trigger the actual VRAM state, but we 
            // signal our intent here for the UI layer.
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
    
    private func getModelURL(for name: String) -> URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return appSupport.appendingPathComponent("EliteAgent/Models/\(name)")
    }
    
    public func complete(_ request: CompletionRequest) async throws -> CompletionResponse {
        let startTime = Date()
        
        // Single prompt construction - InferenceActor handles ChatML specialization
        // We take the last user message or join them.
        let prompt = request.messages.map { $0.role == "user" ? $0.content : "" }.joined(separator: "\n")
        
        // v7.5.0: Pass both system prompt and user prompt to InferenceActor
        let stream = await InferenceActor.shared.generate(
            prompt: prompt, 
            systemPrompt: request.systemPrompt,
            maxTokens: request.maxTokens
        )
        
        var fullContent = ""
        var firstTokenTime: Date?
        var tokenCount = 0
        
        for await chunk in stream {
            if firstTokenTime == nil {
                firstTokenTime = Date()
                let initialLatency = String(format: "%.1fs", firstTokenTime!.timeIntervalSince(startTime))
                AgentLogger.logAudit(level: .info, agent: "titan", message: "Titan: First token arrived (\(initialLatency))")
            }
            fullContent += chunk
            tokenCount += 1 // One chunk is usually one token or a small set of characters
        }
        
        let totalTime = Date().timeIntervalSince(firstTokenTime ?? startTime)
        let tps = totalTime > 0 ? Double(tokenCount) / totalTime : 0
        AgentLogger.logAudit(level: .info, agent: "titan", message: "Titan: Generation speed: \(Int(tps)) t/s")
        
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
