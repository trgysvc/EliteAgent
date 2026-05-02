import Foundation
import MLXLLM
import MLXLMCommon

/// v31.3: Official v3-Native Harpsichord Bridge
/// Orchestrates model routing and lifecycle management for the v3 Titan Engine.
public actor HarpsichordBridge {
    private let vaultManager: VaultManager
    private var providers: [ProviderID: any LLMProvider]
    private let tokenizer: BPETokenizer
    
    public init(vaultManager: VaultManager, providers: [any LLMProvider], tokenizer: BPETokenizer) {
        self.vaultManager = vaultManager
        var dict = [ProviderID: any LLMProvider]()
        for p in providers { dict[p.providerID] = p }
        self.providers = dict
        self.tokenizer = tokenizer
    }
    
    public func routeAndComplete(request: CompletionRequest, preferredProvider: ProviderID? = nil, config: InferenceConfig? = nil) async throws -> CompletionResponse {
        let pID = preferredProvider ?? config?.providerPriority.first ?? .mlx
        
        guard let provider = providers[pID] else {
            throw NSError(domain: "Harpsichord", code: 404, userInfo: [NSLocalizedDescriptionKey: "Provider \(pID) not found"])
        }
        
        // v3-Native: Direct delegation to the chosen provider
        return try await provider.complete(request, useSafeMode: false)
    }
    
    /// v3-Native: Simplified model loading that delegates everything to InferenceActor
    public func loadModel(_ modelId: String, at url: URL) async throws {
        AgentLogger.logInfo("🌉 [v3-Bridge] Routing model load request for: \(modelId)")
        try await InferenceActor.shared.loadModel(at: url)
    }
    
    public func unloadModel() async {
        await InferenceActor.shared.unloadModel()
    }
}

public enum StreamChunk: Sendable {
    case metadata(providerID: ProviderID, isFallback: Bool, latency: Double)
    case text(String)
    case error(String)
}
