import Foundation
import MLXLLM
import MLXVLM
import MLXLMCommon

public enum RoutingError: Error, Sendable, CustomStringConvertible {
    case cloudBlockedByPrivacyGuard
    case noAvailableProviders
    case unsupportedProfile
    case insufficientMemoryForLocal
    
    public var description: String {
        switch self {
        case .cloudBlockedByPrivacyGuard: return "Cloud routing blocked by Privacy Guard."
        case .noAvailableProviders: return "No available LLM providers to route to."
        case .unsupportedProfile: return "Unsupported tracking profile configuration."
        case .insufficientMemoryForLocal: return "Insufficient memory to run local model."
        }
    }
}

public enum InferenceError: Error, Sendable {
    case localProviderUnavailable(String)
}

public actor HarpsichordBridge {
    private let vaultManager: VaultManager
    private var providers: [ProviderID: any LLMProvider]
    private let tokenizer: BPETokenizer
    
    // Stability Debounce
    private var lastProviderID: ProviderID?
    private var lastRouteTime: Date = .distantPast
    private let debounceInterval: TimeInterval = 5.0
    
    public init(vaultManager: VaultManager, providers: [any LLMProvider], tokenizer: BPETokenizer) {
        self.vaultManager = vaultManager
        var dict = [ProviderID: any LLMProvider]()
        for p in providers { dict[p.providerID] = p }
        self.providers = dict
        self.tokenizer = tokenizer
    }
    
    public func routeAndComplete(request: CompletionRequest, preferredProvider: ProviderID? = nil, fallbackProviders: [ProviderID]? = nil, config: InferenceConfig? = nil) async throws -> CompletionResponse {
        
        let effectiveConfig = config ?? InferenceConfig.default
        let policy = effectiveConfig.fallbackPolicy
        let isStrictLocal = policy == .strictLocal || effectiveConfig.strictLocal
        
        // 1. Determine Chain
        var chain: [ProviderID] = []
        if let preferred = preferredProvider {
            chain = [preferred] + (fallbackProviders ?? [])
        } else {
            chain = effectiveConfig.providerPriority
        }
        
        // 2. Strict Local Guard
        if isStrictLocal {
            let localID = chain.first(where: { providers[$0]?.providerType == .local }) ?? .mlx
            guard let provider = providers[localID], provider.providerType == .local else {
                throw InferenceError.localProviderUnavailable("Strict local mode: No local provider available.")
            }
            
            let health = await LocalModelHealthMonitor.shared.runDiagnostics(modelID: AISessionState.shared.selectedModel)
            if health != .healthy {
                throw InferenceError.localProviderUnavailable("Strict local mode: \(health.displayString)")
            }
            
            return try await provider.complete(request, useSafeMode: false)
        }
        
        // 3. Normal Routing
        for (index, pID) in chain.enumerated() {
            guard let provider = providers[pID] else { continue }
            
            // v7.8.5: Health check for local providers in normal routing
            if provider.providerType == .local {
                let health = await LocalModelHealthMonitor.shared.runDiagnostics(modelID: AISessionState.shared.selectedModel)
                if health != .healthy {
                    print("[BRIDGE] Local provider \(pID) unhealthy: \(health.displayString). Processing failure.")
                    if policy == .promptBeforeSwitch || isStrictLocal {
                        throw InferenceError.localProviderUnavailable("Local engine (\(pID.rawValue)): \(health.displayString)")
                    }
                    continue // Auto-fallback case
                }
            }
            
            // Fallback policy check
            if index > 0 {
                let prevID = chain[index - 1]
                if let prev = providers[prevID], prev.providerType == .local && provider.providerType != .local {
                    if policy == .promptBeforeSwitch {
                        throw InferenceError.localProviderUnavailable("Fallback approval required for \(pID.rawValue)")
                    }
                }
            }
            
            if await provider.healthCheck() {
                self.lastProviderID = pID
                self.lastRouteTime = Date()
                return try await provider.complete(request, useSafeMode: false)
            }
        }
        
        throw RoutingError.noAvailableProviders
    }
    
    /// v7.8.0: Metadata-First Streaming (v7.8.5 Refinement)
    public func routeAndStream(request: CompletionRequest, preferredProvider: ProviderID? = nil, config: InferenceConfig? = nil) -> AsyncStream<StreamChunk> {
        return AsyncStream { continuation in
            Task {
                let start = Date()
                let effectiveConfig = config ?? InferenceConfig.default
                let localReady = (await LocalModelHealthMonitor.shared.runDiagnostics(modelID: AISessionState.shared.selectedModel)) == .healthy
                
                var pID = preferredProvider ?? effectiveConfig.providerPriority.first ?? .mlx
                var isFallback = false
                
                if pID == .mlx && !localReady && effectiveConfig.fallbackPolicy != .strictLocal {
                    pID = .openrouter
                    isFallback = true
                }
                
                continuation.yield(.metadata(providerID: pID, isFallback: isFallback, latency: Date().timeIntervalSince(start)))
                
                guard let provider = providers[pID] else {
                    continuation.yield(.error("Provider \(pID) not found"))
                    continuation.finish()
                    return
                }
                
                do {
                    let result = try await provider.complete(request, useSafeMode: false)
                    let words = result.content.split(separator: " ", omittingEmptySubsequences: false)
                    for word in words {
                        try? await Task.sleep(for: .milliseconds(10))
                        continuation.yield(.text(String(word) + " "))
                    }
                    continuation.finish()
                } catch {
                }
            }
        }
    }

    public func loadModel(_ modelId: String, at url: URL) async throws {
        if isVLMModel(modelId) {
            try await loadVLMModel(modelId, at: url)
        } else {
            try await loadLLMModel(modelId, at: url)
        }
    }
    
    private func isVLMModel(_ id: String) -> Bool {
        let lower = id.lowercased()
        let normalized = lower.replacingOccurrences(of: "-", with: "")
        // Match explicit VLM model families only; qwen3/qwen3.5 are text-only models.
        let vlmIndicators = [
            "qwen2vl", "qwen25vl", "qwen3vl",
            "pixtral", "lfm2vl", "llava", "fastvlm",
            "smolvlm", "paligemma", "idefics"
        ]
        if vlmIndicators.contains(where: { normalized.contains($0) }) { return true }
        return lower.contains("-vl-") || lower.hasSuffix("-vl") || lower.contains("-vision-")
    }
    
    private func loadLLMModel(_ id: String, at url: URL) async throws {
        try await InferenceActor.shared.loadModel(at: url)
    }
    
    private func loadVLMModel(_ id: String, at url: URL) async throws {
        try await InferenceActor.shared.loadModel(at: url, asVLM: true)
    }
}

public enum StreamChunk: Sendable {
    case metadata(providerID: ProviderID, isFallback: Bool, latency: Double)
    case text(String)
    case error(String)
}

extension HarpsichordBridge {
    public func getAvailableProviderCount() async -> Int {
        var count = 0
        for p in self.providers.values {
            if await p.healthCheck() {
                count += 1
            }
        }
        return count
    }
    
    public func getAPIKey(for providerID: ProviderID) async throws -> String {
        guard let p = providers[providerID] else {
            throw NSError(domain: "Harpsichord", code: 4, userInfo: [NSLocalizedDescriptionKey: "Provider not found: \(providerID)"])
        }
        
        if let cloud = p as? CloudProvider {
            return try await vaultManager.getAPIKey(for: cloud.providerConf)
        }
        
        throw NSError(domain: "Harpsichord", code: 5, userInfo: [NSLocalizedDescriptionKey: "Provider \(providerID) does not require or support a separate API key fetch in this path."])
    }
}
