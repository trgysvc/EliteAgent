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
        
        self.models = localModels + openRouterModels
        
        // Match current selection from vault if possible
        updateSelectionFromVault()
        
        isLoading = false
    }
    
    private func fetchOpenRouterModels() async -> [ModelSource] {
        guard let url = URL(string: "https://openrouter.ai/api/v1/models") else { return [] }
        
        // We need the API key from VaultManager
        let defaultVaultPath = URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent(".eliteagent/vault.plist")
        guard let vault = try? VaultManager(configURL: defaultVaultPath) else { return [] }
        
        guard let providerConf = vault.config.providers.first(where: { $0.id == "openai" }),
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
            }
            let pricing: Pricing
            let context_length: Int?
        }
        
        struct ORResponse: Codable {
            let data: [ORModel]
        }
        
        guard let decoded = try? JSONDecoder().decode(ORResponse.self, from: data) else { return [] }
        
        // Filter: show free models and popular ones (sorting by popular first - assumed in order or we can filter)
        // For now, let's take models where prompt pricing is "0" or just first 20
        return decoded.data.prefix(20).map { model in
            let isFree = model.pricing.prompt == "0"
            return .openRouter(
                id: model.id,
                name: model.name,
                isFree: isFree,
                contextK: (model.context_length ?? 0) / 1000,
                costPer1K: Decimal(string: model.pricing.prompt)
            )
        }
    }
    
    public func selectModel(_ model: ModelSource) {
        self.selected = model
        
        let defaultVaultPath = URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent(".eliteagent/vault.plist")
        guard let vault = try? VaultManager(configURL: defaultVaultPath) else { return }
        
        Task {
            do {
                try await vault.updateModelName(for: "openai", to: model.id)
                print("[ModelPicker] Model changed to \(model.name)")
                // Note: Orchestrator currently re-loads vault on each submitTask,
                // so we don't need to manually tell it to reload internal state,
                // but we might want to update orchestrator.providerUsed for the UI.
                // orchestrator.providerUsed = model.name
            } catch {
                print("[ModelPicker] Failed to update model: \(error)")
            }
        }
    }
    
    private func updateSelectionFromVault() {
        let defaultVaultPath = URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent(".eliteagent/vault.plist")
        guard let vault = try? VaultManager(configURL: defaultVaultPath),
              let modelName = vault.config.providers.first(where: { $0.id == "openai" })?.modelName else {
            return
        }
        
        if let match = models.first(where: { $0.id == modelName }) {
            self.selected = match
        }
    }
}
