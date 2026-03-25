import Foundation

public actor MLXProvider: LocalLLMProvider {
    public nonisolated let providerID: ProviderID
    public nonisolated let providerType: ProviderType = .local
    public let capabilities: Set<Capability> = [.think, .code, .general]
    public let costPer1KTokens: Decimal = 0
    public let maxContextTokens: Int = 131072
    public private(set) var status: ProviderStatus = .ready
    
    private var model: LLMModel?
    
    public init(providerID: ProviderID) {
        self.providerID = providerID
        self.status = .ready // For mock
    }
    
    public func healthCheck() async -> Bool {
        return model != nil
    }
    
    public func loadModel(_ modelName: String) async throws {
        self.status = .loading
        do {
            self.model = try await LLMModel.load(modelName)
            self.status = .ready
        } catch {
            self.status = .error
            throw error
        }
    }
    
    public func complete(_ request: CompletionRequest) async throws -> CompletionResponse {
        guard let model = model else { throw ProviderError.modelNotLoaded }
        
        let output = try await model.generate(
            systemPrompt: request.systemPrompt,
            messages: request.messages,
            maxTokens: request.maxTokens,
            temperature: request.temperature ?? 0.2
        )
        
        return CompletionResponse(
            taskID: request.taskID,
            providerUsed: providerID,
            content: output.text,
            thinkBlock: output.thinkBlock,
            tokensUsed: output.tokenCount,
            latencyMs: output.latencyMs,
            costUSD: self.costPer1KTokens * Decimal((output.tokenCount.total) / 1000)
        )
    }
}
