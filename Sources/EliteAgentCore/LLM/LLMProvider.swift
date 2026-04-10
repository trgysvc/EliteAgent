import Foundation

public protocol LLMProvider: Actor {
    nonisolated var providerID: ProviderID { get }
    nonisolated var providerType: ProviderType { get }
    var capabilities: Set<Capability> { get }
    var costPer1KTokens: Decimal { get }
    var maxContextTokens: Int { get }
    var status: ProviderStatus { get }

    func healthCheck() async -> Bool
    func complete(_ request: CompletionRequest, useSafeMode: Bool) async throws -> CompletionResponse
}

public protocol LocalLLMProvider: LLMProvider {}

