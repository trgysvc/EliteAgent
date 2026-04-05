import Foundation
import SwiftUI
import Combine

@MainActor
public class ModelPickerViewModel: ObservableObject {
    @Published public var models: [ModelSource] = []
    @Published public var selected: ModelSource?
    @Published public var isLoading: Bool = false
    @Published public var searchText: String = ""
    @Published public var alertMessage: String?
    
    private var cancellables = Set<AnyCancellable>()
    
    private let orchestrator: Orchestrator
    
    // Computed Filtered Properties
    public var filteredLocalModels: [ModelSource] {
        let allLocal = models.filter { model in
            if case .localMLX(let id, _, _, _) = model {
                // v7.8.6: Technical disk check for local availability
                let path = ModelSetupManager.shared.getModelDirectory(for: id)
                return FileManager.default.fileExists(atPath: path.path)
            }
            return false
        }
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
                let path = ModelSetupManager.shared.getModelDirectory(for: id)
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
    
    // v7.9.0: Provider Availability Flags
    @Published public var hasTitanEngine: Bool = false
    @Published public var hasOllama: Bool = false
    @Published public var hasOpenRouter: Bool = false
    
    public init(orchestrator: Orchestrator) {
        self.orchestrator = orchestrator
        
        // Listen for model setup errors to show alerts
        ModelSetupManager.shared.$errorMessage
            .receive(on: RunLoop.main)
            .assign(to: \.alertMessage, on: self)
            .store(in: &cancellables)
            
        // v9.9: Sync with ModelStateManager
        ModelStateManager.shared.$currentModelID
            .receive(on: RunLoop.main)
            .sink { [weak self] modelID in
                if let modelID = modelID {
                    self?.selected = self?.models.first(where: { $0.id == modelID })
                }
            }
            .store(in: &cancellables)
            
        NotificationCenter.default.publisher(for: NSNotification.Name("CredentialsUpdated"))
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                Task { [weak self] in
                    await self?.loadModels()
                }
            }
            .store(in: &cancellables)
            
        // v9.1: Live Refresh when a model is activated in Model Center
        NotificationCenter.default.publisher(for: .activeProviderChanged)
            .receive(on: RunLoop.main)
            .sink { [weak self] note in
                Task { [weak self] in
                    await self?.loadModels()
                    if let modelID = note.object as? String {
                        self?.selected = self?.models.first(where: { $0.id == modelID })
                    }
                }
            }
            .store(in: &cancellables)
    }
    
    public func loadModels() async {
        isLoading = true
        
        // 1. Dynamic Titan Engine Discovery (MLX) - v9.1 Unified
        let localCandidates = ModelRegistry.availableModels.filter { catalog in
            if case .localTitanEngine = catalog.provider { return true }
            return false
        }
        
        let localModels: [ModelSource] = localCandidates.compactMap { catalog in
            let path = ModelManager.shared.modelsDirectory.appendingPathComponent(catalog.id)
            let isInstalled = FileManager.default.fileExists(atPath: path.appendingPathComponent("config.json").path)
            
            if isInstalled {
                return ModelSource.localMLX(id: catalog.id, name: catalog.name, ramGB: 16, hasThink: catalog.id.contains("think"))
            }
            return nil
        }
        self.hasTitanEngine = !localModels.isEmpty
        
        // 2. Ollama Bridge Discovery (Dinamik)
        let ollamaModels = await OllamaManager.shared.fetchModels()
        self.hasOllama = !ollamaModels.isEmpty
        
        // 3. OpenRouter Cloud Discovery (Dinamik)
        let openRouterModels = await fetchOpenRouterModels()
        self.hasOpenRouter = !openRouterModels.isEmpty
        
        // 4. Custom Vault Models
        let (customModels, _) = loadVaultModels()
        
        self.models = localModels + ollamaModels + openRouterModels + customModels
        
        // 5. Persisted Selection Sync
        if let activeID = ModelSetupManager.shared.activeModelID.isEmpty ? nil : ModelSetupManager.shared.activeModelID, 
           let current = models.first(where: { $0.id == activeID }) {
            self.selected = current
        } else {
            // v7.9.0: Priority-based selection on fresh state
            autoSelectPreferredModel()
        }
        
        isLoading = false
    }
    
    public func autoSelectPreferredModel() {
        // v7.9.0 Priority Cascade: Titan > OpenRouter > Ollama
        
        // a. Titan Engine (MLX Local)
        if hasTitanEngine {
            if let qwen = models.first(where: { if case .localMLX = $0 { return true }; return false }) {
                self.selectModel(qwen)
                return
            }
        }
        
        // b. OpenRouter (Cloud - Gemini Flash Priority)
        if hasOpenRouter {
            let preferred = ["google/gemini-2.0-flash-001", "google/gemini-flash-1.5"]
            for id in preferred {
                if let model = models.first(where: { $0.id == id }) {
                    self.selectModel(model)
                    return
                }
            }
        }
        
        // c. Ollama (Bridge Local)
        if hasOllama {
            if let firstOllama = models.first(where: { if case .bridge = $0 { return true }; return false }) {
                self.selectModel(firstOllama)
                return
            }
        }
    }
    
    public func selectModel(_ model: ModelSource) {
        self.selected = model
        
        // v7.8.6: Persist selection to core system
        ModelSetupManager.shared.activeModelID = model.id
        
        // Push notification for UI sync
        NotificationCenter.default.post(name: NSNotification.Name("ModelSelected"), object: model)
        
        // v7.8.0 Sync technical ID to centralized state for HarpsichordBridge
        AISessionState.shared.selectedModel = model.id
        
        let defaultVaultPath = PathConfiguration.shared.vaultURL
        guard let vault = try? VaultManager(configURL: defaultVaultPath) else { return }
        
        Task {
            do {
                if case .openRouter(let id, _, _, _, let prompt, let completion) = model {
                    try await vault.updateModelPricing(for: "openrouter", modelName: id, promptPrice: prompt, completionPrice: completion)
                    
                    // v9.9: Force switch to Cloud in StateManager
                    ModelStateManager.shared.activeProvider = .cloudOpenRouter(modelID: id)
                    ModelStateManager.shared.currentModelID = id
                    ModelStateManager.shared.isCloudFallback = false // Clean manual selection
                    
                } else if case .localMLX(let id, _, _, _) = model {
                    try await vault.updateModelPricing(for: "mlx", modelName: id, promptPrice: 0, completionPrice: 0)
                    
                    // v9.9: Unified Local Switch with Priming
                    try await ModelStateManager.shared.switchToLocal(id)
                    
                    // If files are missing, trigger download
                    if !ModelSetupManager.shared.isModelReady && ModelSetupManager.shared.state != .loading {
                        ModelSetupManager.shared.startModelDownload()
                    }
                } else if case .bridge(let id, _) = model {
                    try await vault.updateModelPricing(for: "bridge", modelName: id, promptPrice: 0, completionPrice: 0)
                    ModelStateManager.shared.activeProvider = .localOllama(modelName: id)
                    ModelStateManager.shared.currentModelID = id
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
                self.alertMessage = "Model yükleme hatası: \(error.localizedDescription)"
            }
        }
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
        
        // v7.8.9: Force re-load VaultManager to pick up newly saved Keychain tokens & Provider definitions
        let defaultVaultPath = PathConfiguration.shared.vaultURL
        guard let vault = try? VaultManager(configURL: defaultVaultPath) else { 
            print("[ModelPicker] Failed to reload VaultManager for OpenRouter fetch")
            return [] 
        }
        
        // v7.8.9: Strictly check for 'openrouter' ID in the config
        guard let providerConf = vault.config.providers.first(where: { $0.id == "openrouter" }),
              let apiKey = try? await vault.getAPIKey(for: providerConf) else {
            print("[ModelPicker] OpenRouter provider or key NOT found in Vault config")
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
