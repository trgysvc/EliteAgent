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

public actor HarpsichordBridge {
    private let vaultManager: VaultManager
    private let providers: [ProviderID: any LLMProvider]
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
    
    public func routeAndComplete(request: CompletionRequest, preferredProvider: ProviderID, fallbackProviders: [ProviderID]) async throws -> CompletionResponse {
        let strategy = vaultManager.config.routingStrategy
        
        // 1. Check Stability Debounce (Sticky Provider)
        if let lastID = lastProviderID, Date().timeIntervalSince(lastRouteTime) < debounceInterval {
            if let stickyProvider = providers[lastID] {
                // Verify sensitivity allows this sticky provider
                if request.sensitivityLevel != .confidential || stickyProvider.providerType != .cloud {
                    do {
                        return try await stickyProvider.complete(request)
                    } catch {
                        // Fall through to normal routing if sticky fails
                    }
                }
            }
        }
        
        // 2. Privacy Guard Override
        let isLocalForced = request.sensitivityLevel == .confidential
        
        if isLocalForced && strategy == .cloudOnly {
            throw RoutingError.cloudBlockedByPrivacyGuard
        }
        
        // 3. Token-Based Routing
        let fullPrompt = request.systemPrompt + "\n" + request.messages.map(\.content).joined(separator: "\n")
        let tokenCount = tokenizer.encode(text: fullPrompt).count
        
        // Complexity check (PRD 6.2 style)
        // If token count > 8000 or user-set complexity >= 4, prefer Cloud
        let refinedComplexity = (tokenCount > 8000) ? 5 : request.complexity
        
        var selectedProviderID: ProviderID
        
        switch strategy {
        case .cloudOnly:
            selectedProviderID = try await executeWithFallbacks(request: request, providersToTry: fallbackProviders + [preferredProvider], localForced: isLocalForced).providerUsed
            
        case .localFirst:
            selectedProviderID = try await prepareExecution(request: request, chain: [preferredProvider] + fallbackProviders, localForced: isLocalForced)
            
        case .hybrid:
            if refinedComplexity < 4 {
                selectedProviderID = try await prepareExecution(request: request, chain: [preferredProvider] + fallbackProviders, localForced: isLocalForced)
            } else {
                if isLocalForced {
                    selectedProviderID = try await prepareExecution(request: request, chain: [preferredProvider] + fallbackProviders, localForced: true)
                } else {
                    selectedProviderID = try await prepareExecution(request: request, chain: fallbackProviders + [preferredProvider], localForced: false)
                }
            }
        case .bridgeFirst:
            // Bridge-First Routing: Favor the 'bridge' (Ollama) provider, then Titan (Local), then Cloud.
            selectedProviderID = try await prepareExecution(request: request, chain: ["bridge"] + [preferredProvider] + fallbackProviders, localForced: isLocalForced)
        }
        
        // Final Execution (if not already completed by logic above - simplified for this update)
        guard let finalProvider = providers[selectedProviderID] else {
            throw RoutingError.noAvailableProviders
        }
        
        // Update Debounce state
        if self.lastProviderID != selectedProviderID {
            let pID = selectedProviderID
            await MainActor.run {
                NotificationCenter.default.post(name: .llmProviderSwitched, object: nil, userInfo: ["provider": pID.rawValue])
            }
        }
        self.lastProviderID = selectedProviderID
        self.lastRouteTime = Date()
        
        return try await finalProvider.complete(request)
    }
    
    private func prepareExecution(request: CompletionRequest, chain: [ProviderID], localForced: Bool) async throws -> ProviderID {
        for pID in chain {
            guard let provider = providers[pID] else { continue }
            
            if localForced && provider.providerType == .cloud { continue }
            
            // Memory Check for Local (MLX)
            if provider.providerType == .local {
                #if os(macOS)
                // Threshold: available RAM < 2GB -> skip local
                if ProcessInfo.processInfo.isLowPowerModeEnabled || !hasAvailableMemory(required: 2_000_000_000) {
                    await MainActor.run {
                        NotificationCenter.default.post(name: .llmMemoryPressureAvoided, object: nil)
                    }
                    continue 
                }
                #endif
            }
            
            if await provider.healthCheck() {
                return pID
            }
        }
        throw RoutingError.noAvailableProviders
    }
    
    private func hasAvailableMemory(required: UInt64) -> Bool {
        // Fallback for simple implementation until low-level bridge is ready
        // In a real implementation we would call os_proc_available_memory() via a bridge
        return true 
    }
    
    private func executeWithFallbacks(request: CompletionRequest, providersToTry: [ProviderID], localForced: Bool) async throws -> CompletionResponse {
        var lastError: Error?
        
        for pID in providersToTry {
            guard let provider = providers[pID] else { continue }
            
            if localForced && provider.providerType == .cloud {
                lastError = RoutingError.cloudBlockedByPrivacyGuard
                continue
            }
            
            do {
                let response = try await provider.complete(request)
                return response
            } catch {
                lastError = error
                continue
            }
        }
        
        throw lastError ?? RoutingError.noAvailableProviders
    }
}
