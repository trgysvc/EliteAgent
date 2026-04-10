import Foundation

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
                
                // 1. Diagnostics & Selection
                let localReady = (await LocalModelHealthMonitor.shared.runDiagnostics(modelID: AISessionState.shared.selectedModel)) == .healthy
                
                var pID = preferredProvider ?? effectiveConfig.providerPriority.first ?? .mlx
                var isFallback = false
                
                // If local requested but not ready, and not in strict mode, fallback to cloud
                if pID == .mlx && !localReady && effectiveConfig.fallbackPolicy != .strictLocal {
                    pID = .openrouter
                    isFallback = true
                }
                
                // 2. Emit Metadata FIRST
                continuation.yield(.metadata(providerID: pID, isFallback: isFallback, latency: Date().timeIntervalSince(start)))
                
                // 3. Execution (Bridging to providers)
                guard let provider = providers[pID] else {
                    continuation.yield(.error("Provider \(pID) not found"))
                    continuation.finish()
                    return
                }
                
                do {
                    // For now, most providers use routeAndComplete bridge.
                    // In v7.9, we will implement native AsyncStream for each provider.
                    let result = try await provider.complete(request, useSafeMode: false)
                    
                    // Simulate stream for immediate UI feedback
                    let words = result.content.split(separator: " ", omittingEmptySubsequences: false)
                    for word in words {
                        try? await Task.sleep(for: .milliseconds(10)) // Smooth streaming feel
                        continuation.yield(.text(String(word) + " "))
                    }
                    
                    continuation.finish()
                } catch {
                    continuation.yield(.error(error.localizedDescription))
                    continuation.finish()
                }
            }
        }
    }

public enum StreamChunk: Sendable {
    case metadata(providerID: ProviderID, isFallback: Bool, latency: Double)
    case text(String)
    case error(String)
}
    
    // v7.9.1: Silent Fail for Ollama
    private func checkOllamaAvailability() async -> Bool {
        #if DEBUG
        print("[TRACE] HarpsichordBridge: Checking Ollama at localhost:11434")
        #endif
        
        guard let url = URL(string: "http://localhost:11434/api/tags") else { return false }
        var request = URLRequest(url: url)
        request.timeoutInterval = 1.0
        
        do {
            let (_, response) = try await URLSession.shared.data(for: request)
            return (response as? HTTPURLResponse)?.statusCode == 200
        } catch {
            #if DEBUG
            print("[TRACE] HarpsichordBridge: Ollama not available: \(error.localizedDescription)")
            #endif
            return false
        }
    }
    
    // v7.1 Additions for Config-Driven logic
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
