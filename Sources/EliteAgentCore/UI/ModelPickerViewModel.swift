import Foundation
import SwiftUI
import Combine

@MainActor
public class ModelPickerViewModel: ObservableObject {
    @Published public var models: [ModelSource] = []
    @Published public var selected: ModelSource?
    @Published public var isLoading: Bool = false
    
    private let orchestrator: Orchestrator
    
    public var localModels: [ModelSource] {
        models.filter { if case .localMLX = $0 { return true }; return false }
    }
    
    public var cloudModels: [ModelSource] {
        models.filter { if case .openRouter = $0 { return true }; return false }
              .sorted { $0.totalPrice < $1.totalPrice }
    }
    
    public init(orchestrator: Orchestrator) {
        self.orchestrator = orchestrator
    }
    
    public func loadModels() async {
        isLoading = true
        
        // 1. Static local MLX list (from PRD/user template)
        let localModels: [ModelSource] = [
            .localMLX(id: "mlx-r1-32b", name: "DeepSeek R1 32B", ramGB: 96, hasThink: true),
            .localMLX(id: "mlx-r1-8b", name: "DeepSeek R1 8B", ramGB: 16, hasThink: true),
            .localMLX(id: "mlx-llama3-8b", name: "Llama 3 8B", ramGB: 16, hasThink: false),
        ]
        
        // 2. Fetch OpenRouter models via API
        let openRouterModels = await fetchOpenRouterModels()
        
        // 3. Load custom models from Vault
        let customModels = loadCustomModelsFromVault()
        
        self.models = localModels + openRouterModels + customModels
        
        // Match current selection from vault if possible
        updateSelectionFromVault()
        
        isLoading = false
    }
    
    private func loadCustomModelsFromVault() -> [ModelSource] {
        let defaultVaultPath = URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent(".eliteagent/vault.plist")
        guard let vault = try? VaultManager(configURL: defaultVaultPath) else { return [] }
        
        return vault.config.providers.filter { $0.id.hasPrefix("custom-") }.map { provider in
            .custom(
                providerID: provider.id,
                name: provider.id.replacingOccurrences(of: "custom-", with: ""), // Or store a real display name
                modelID: provider.modelName ?? "unknown",
                type: provider.type,
                isReasoning: provider.capabilities?.contains("reasoning") ?? false
            )
        }
    }
    
    private func fetchOpenRouterModels() async -> [ModelSource] {
        guard let url = URL(string: "https://openrouter.ai/api/v1/models") else { return [] }
        
        // We need the API key from VaultManager
        let defaultVaultPath = URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent(".eliteagent/vault.plist")
        guard let vault = try? VaultManager(configURL: defaultVaultPath) else { return [] }
        
        guard let providerConf = vault.config.providers.first(where: { $0.id == "openrouter" }),
              let apiKey = try? await vault.getAPIKey(for: providerConf) else {
            return []
        }
        
        var request = URLRequest(url: url)
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("https://eliteagent.app", forHTTPHeaderField: "HTTP-Referer")
        request.setValue("EliteAgent/1.0", forHTTPHeaderField: "X-Title")
        
        guard let (data, _) = try? await URLSession.shared.data(for: request) else { return [] }
        
        struct ORModel: Codable {
            let id: String
            let name: String
            struct Pricing: Codable {
                let prompt: String
                let completion: String
            }
            let pricing: Pricing
            let context_length: Int?
        }
        
        struct ORResponse: Codable {
            let data: [ORModel]
        }
        
        guard let decoded = try? JSONDecoder().decode(ORResponse.self, from: data) else { return [] }
        
        return decoded.data.map { model in
            let isFree = model.pricing.prompt == "0"
            return .openRouter(
                id: model.id,
                name: model.name,
                isFree: isFree,
                contextK: (model.context_length ?? 0) / 1000,
                promptPrice: Decimal(string: model.pricing.prompt),
                completionPrice: Decimal(string: model.pricing.completion)
            )
        }
    }
    
    public func selectModel(_ model: ModelSource) {
        self.selected = model
        
        let defaultVaultPath = URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent(".eliteagent/vault.plist")
        guard let vault = try? VaultManager(configURL: defaultVaultPath) else { return }
        
        Task {
            do {
                if case .openRouter(let id, _, _, _, let prompt, let completion) = model {
                    try await vault.updateModelPricing(for: "openrouter", modelName: id, promptPrice: prompt, completionPrice: completion)
                } else if case .localMLX(let id, _, _, _) = model {
                    try await vault.updateModelPricing(for: "mlx", modelName: id, promptPrice: 0, completionPrice: 0)
                } else if case .custom(let providerID, _, let modelID, _, _) = model {
                    // Custom models use their own provider ID
                    try await vault.updateModelPricing(for: providerID, modelName: modelID)
                }
                print("[ModelPicker] Model and Pricing changed to \(model.name)")
            } catch {
                print("[ModelPicker] Failed to update model: \(error)")
            }
        }
    }
    
    private func updateSelectionFromVault() {
        let defaultVaultPath = URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent(".eliteagent/vault.plist")
        guard let vault = try? VaultManager(configURL: defaultVaultPath) else { return }
        
        // Try to find any provider that is currently "active"
        for provider in vault.config.providers {
            if let activeModelName = provider.modelName, let match = models.first(where: { 
                if case .custom(let pid, _, _, _, _) = $0 { return pid == provider.id }
                return $0.id == activeModelName 
            }) {
                self.selected = match
                return
            }
        }
        
        // Fallback to Gemini 3.1 Flash Lite
        if let fallback = models.first(where: { $0.id == "google/gemini-3.1-flash-lite-preview" }) {
            self.selected = fallback
        }
    }
}
