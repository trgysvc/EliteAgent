import Foundation
import SwiftUI
import Combine

@MainActor
public class ModelPickerViewModel: ObservableObject {
    @Published public var models: [ModelSource] = []
    @Published public var selected: ModelSource?
    @Published public var isLoading: Bool = false
    @Published public var searchText: String = ""
    
    private let orchestrator: Orchestrator
    
    // Computed Filtered Properties
    public var filteredLocalModels: [ModelSource] {
        let allLocal = models.filter { if case .localMLX = $0 { return true }; return false }
        if searchText.isEmpty { return allLocal }
        return allLocal.filter { $0.name.localizedCaseInsensitiveContains(searchText) }
    }
    
    public var filteredOllamaModels: [ModelSource] {
        let allOllama = models.filter { if case .bridge = $0 { return true }; return false }
        if searchText.isEmpty { return allOllama }
        return allOllama.filter { $0.name.localizedCaseInsensitiveContains(searchText) }
    }
    
    public var filteredCloudModels: [ModelSource] {
        let allCloud = models.filter { if case .openRouter = $0 { return true }; return false }
                            .sorted { $0.totalPrice < $1.totalPrice }
        if searchText.isEmpty { return allCloud }
        return allCloud.filter { $0.name.localizedCaseInsensitiveContains(searchText) }
    }
    
    // For AI Dashboard
    public var installedLocalModels: [ModelSource] {
        models.filter { model in
            if case .localMLX(let id, _, _, _) = model {
                let path = ModelSetupManager.shared.getModelDirectory().deletingLastPathComponent().appendingPathComponent(id)
                return FileManager.default.fileExists(atPath: path.path)
            }
            return false
        }
    }
    
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
        
        // 1. Dynamic Titan Engine Discovery (MLX)
        var localModels: [ModelSource] = []
        if ModelSetupManager.shared.isModelReady {
            localModels.append(.localMLX(id: "Qwen2.5-7B-Instruct-4bit", name: "Qwen 2.5 7B (Titan)", ramGB: 16, hasThink: false))
        }
        
        // 2. Load Custom & Bridge Models from Vault
        let (customModels, bridgeModels) = loadVaultModels()
        
        // 3. Fetch OpenRouter models via API
        let openRouterModels = await fetchOpenRouterModels()
        
        self.models = localModels + bridgeModels + openRouterModels + customModels
        
        // 4. Auto-select Titan if ready
        if ModelSetupManager.shared.isModelReady, let titan = models.first(where: { $0.id == "Qwen2.5-7B-Instruct-4bit" }) {
            self.selected = titan
        } else {
            updateSelectionFromVault()
        }
        
        isLoading = false
    }
    
    private func loadVaultModels() -> (custom: [ModelSource], bridge: [ModelSource]) {
        let defaultVaultPath = PathConfiguration.shared.vaultURL
        guard let vault = try? VaultManager(configURL: defaultVaultPath) else { return ([], []) }
        
        let custom = vault.config.providers.filter { $0.id.hasPrefix("custom-") }.map { provider in
            ModelSource.custom(
                providerID: provider.id,
                name: provider.id.replacingOccurrences(of: "custom-", with: ""),
                modelID: provider.modelName ?? "unknown",
                type: provider.type,
                isReasoning: provider.capabilities?.contains("reasoning") ?? false
            )
        }
        
        let bridge = vault.config.providers.filter { $0.type == .bridge }.map { provider in
            ModelSource.bridge(id: provider.modelName ?? "ollama-model", name: provider.id == "bridge" ? "Ollama / Local" : provider.id)
        }
        
        return (custom, bridge)
    }
    
    private func fetchOpenRouterModels() async -> [ModelSource] {
        guard let url = URL(string: "https://openrouter.ai/api/v1/models") else { return [] }
        
        // We need the API key from VaultManager
        let defaultVaultPath = PathConfiguration.shared.vaultURL
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
        
        let defaultVaultPath = PathConfiguration.shared.vaultURL
        guard let vault = try? VaultManager(configURL: defaultVaultPath) else { return }
        
        Task {
            do {
                if case .openRouter(let id, _, _, _, let prompt, let completion) = model {
                    try await vault.updateModelPricing(for: "openrouter", modelName: id, promptPrice: prompt, completionPrice: completion)
                } else if case .localMLX(let id, _, _, _) = model {
                    try await vault.updateModelPricing(for: "mlx", modelName: id, promptPrice: 0, completionPrice: 0)
                } else if case .bridge(let id, _) = model {
                    try await vault.updateModelPricing(for: "bridge", modelName: id, promptPrice: 0, completionPrice: 0)
                } else if case .custom(let providerID, _, let modelID, _, _) = model {
                    try await vault.updateModelPricing(for: providerID, modelName: modelID)
                }
                print("[ModelPicker] Model and Pricing changed to \(model.name)")
                
                // v7.4.0 LiveSwitch: Notify Orchestrator of provider change immediately
                await MainActor.run {
                    NotificationCenter.default.post(
                        name: .activeProviderChanged,
                        object: nil,
                        userInfo: ["model": model]
                    )
                }
            } catch {
                print("[ModelPicker] Failed to update model: \(error)")
            }
        }
    }
    
    private func updateSelectionFromVault() {
        let defaultVaultPath = PathConfiguration.shared.vaultURL
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
