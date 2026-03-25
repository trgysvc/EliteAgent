import Foundation

public enum RoutingError: Error, Sendable, CustomStringConvertible {
    case cloudBlockedByPrivacyGuard
    case noAvailableProviders
    case unsupportedProfile
    
    public var description: String {
        switch self {
        case .cloudBlockedByPrivacyGuard: return "Cloud routing blocked by Privacy Guard."
        case .noAvailableProviders: return "No available LLM providers to route to."
        case .unsupportedProfile: return "Unsupported tracking profile configuration."
        }
    }
}

public actor HarpsichordBridge {
    private let vaultManager: VaultManager
    private let providers: [ProviderID: any LLMProvider]
    
    public init(vaultManager: VaultManager, providers: [any LLMProvider]) {
        self.vaultManager = vaultManager
        var dict = [ProviderID: any LLMProvider]()
        for p in providers { dict[p.providerID] = p }
        self.providers = dict
    }
    
    public func routeAndComplete(request: CompletionRequest, preferredProvider: ProviderID, fallbackProviders: [ProviderID]) async throws -> CompletionResponse {
        let strategy = vaultManager.config.routingStrategy
        
        // 1. Privacy Guard Override
        let isLocalForced = request.sensitivityLevel == .confidential
        
        if isLocalForced && strategy == .cloudOnly {
            throw RoutingError.cloudBlockedByPrivacyGuard
        }
        
        switch strategy {
        case .cloudOnly:
            return try await executeWithFallbacks(request: request, providersToTry: fallbackProviders + [preferredProvider], localForced: isLocalForced)
            
        case .localFirst:
            var localChain = [preferredProvider]
            localChain.append(contentsOf: fallbackProviders)
            return try await executeWithFallbacks(request: request, providersToTry: localChain, localForced: isLocalForced)
            
        case .hybrid:
            if request.complexity < 3 {
                return try await executeWithFallbacks(request: request, providersToTry: [preferredProvider] + fallbackProviders, localForced: isLocalForced)
            } else {
                if isLocalForced {
                    return try await executeWithFallbacks(request: request, providersToTry: [preferredProvider] + fallbackProviders, localForced: true)
                } else {
                    return try await executeWithFallbacks(request: request, providersToTry: fallbackProviders + [preferredProvider], localForced: false)
                }
            }
        }
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
