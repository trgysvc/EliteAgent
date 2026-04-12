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
    
    @Published public var filteredLocalModels: [ModelCatalog] = []
    @Published public var installedLocalModels: [ModelCatalog] = []
    @Published public var filteredCloudModels: [ModelSource] = []
    
    // v7.9.0: Provider Availability Flags
    @Published public var hasTitanEngine: Bool = false
    @Published public var hasOpenRouter: Bool = false
    
    public init() {
        // v9.9.8: Immediate load on startup (Atomic Sync)
        Task {
            await loadModels()
        }
        
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
            
        // v9.9.6: High-frequency sync with ModelManager
        NotificationCenter.default.publisher(for: .modelsDidChange)
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                Task { [weak self] in
                    await self?.loadModels()
                }
            }
            .store(in: &cancellables)
            
        NotificationCenter.default.publisher(for: .activeProviderChanged)
            .receive(on: RunLoop.main)
            .sink { [weak self] note in
                // v10.0.1: Only reload if the notification came from an external source 
                // to prevent the self-triggering loop during loadModels() -> selectModel()
                if note.userInfo?["source"] as? String != "ModelPickerViewModel" {
                    Task { [weak self] in
                        await self?.loadModels()
                        if let modelID = note.object as? String {
                            self?.selected = self?.models.first(where: { $0.id == modelID })
                        }
                    }
                }
            }
            .store(in: &cancellables)
    }
    
    public func loadModels() async {
        guard !isLoading else { return }
        
        await MainActor.run {
            self.isLoading = true
        }
        
        print("🔍 [DEBUG] Loading models (Atomic RED FIX)...")
        
        // 1. Collect all local data (Background)
        let registry = ModelRegistry.availableModels
        var installed: [ModelCatalog] = []
        let localTitanModels = registry.filter { if case .localTitanEngine = $0.provider { return true }; return false }
        
        for catalog in localTitanModels {
            let path = ModelManager.shared.modelsDirectory.appendingPathComponent(catalog.id)
            let configExists = FileManager.default.fileExists(atPath: path.appendingPathComponent("config.json").path)
            if configExists {
                installed.append(catalog)
            }
        }
        
        let openRouter = await fetchOpenRouterModels()
        
        // 3. Atomic UI Update (Main Thread)
        await MainActor.run {
            self.installedLocalModels = installed
            self.filteredLocalModels = localTitanModels // Keep all for Wizard
            self.filteredCloudModels = openRouter
            
            // Rebuild the master models list: ONLY INSTALLED/ACCESSIBLE
            var newModels: [ModelSource] = []
            
            // Add ONLY INSTALLED Local Titan models
            newModels.append(contentsOf: installed.map { catalog in
                .localMLX(id: catalog.id, name: catalog.name, ramGB: 16, hasThink: catalog.id.contains("think"))
            })
            
            newModels.append(contentsOf: openRouter)
            
            self.models = newModels
            
            // Provider flags: True only if actually usable
            self.hasTitanEngine = !installed.isEmpty
            self.hasOpenRouter = !openRouter.isEmpty
            
            print("✅ [DEBUG] Atomic update: installed=\(installed.count), totalUsable=\(self.models.count)")
            
            // Selection Sync: Only sync if the model is actually in our NEW filtered list
            if let activeID = ModelSetupManager.shared.activeModelID.isEmpty ? nil : ModelSetupManager.shared.activeModelID, 
               let current = models.first(where: { $0.id == activeID }) {
                self.selected = current
            } else {
                autoSelectPreferredModel()
            }
            
            self.isLoading = false
            self.objectWillChange.send()
        }
    }
    
    public func autoSelectPreferredModel() {
        if hasTitanEngine {
            if let firstLocal = models.first(where: { if case .localMLX = $0 { return true }; return false }) {
                self.selectModel(firstLocal)
                return
            }
        }
        
        if hasOpenRouter {
            let preferred = ["google/gemini-2.0-flash-001", "google/gemini-flash-1.5"]
            for id in preferred {
                if let model = models.first(where: { $0.id == id }) {
                    self.selectModel(model)
                    return
                }
            }
        }
    }
    
    public func selectModel(_ model: ModelSource) {
        self.selected = model
        ModelSetupManager.shared.activeModelID = model.id
        
        DispatchQueue.main.async {
            NotificationCenter.default.post(name: NSNotification.Name("ModelSelected"), object: model)
            AISessionState.shared.selectedModel = model.id
        }
        
        let defaultVaultPath = PathConfiguration.shared.vaultURL
        guard let vault = try? VaultManager(configURL: defaultVaultPath) else { return }
        
        Task {
                switch model {
                case .openRouter(let id, _, _, _, let prompt, let completion):
                    try? await vault.updateModelPricing(for: "openrouter", modelName: id, promptPrice: prompt, completionPrice: completion)
                    ModelStateManager.shared.activeProvider = .cloudOpenRouter(modelID: id)
                    ModelStateManager.shared.currentModelID = id
                    ModelStateManager.shared.isCloudFallback = false
                    
                case .localMLX(let id, _, _, _):
                    try? await vault.updateModelPricing(for: "mlx", modelName: id, promptPrice: 0, completionPrice: 0)
                    try? await ModelStateManager.shared.switchToLocal(id)
                    if !ModelSetupManager.shared.isModelReady && ModelSetupManager.shared.state != .loading {
                        ModelSetupManager.shared.startModelDownload()
                    }
                    
                
                default: break
                }
                
                await MainActor.run {
                    NotificationCenter.default.post(
                        name: .activeProviderChanged,
                        object: nil,
                        userInfo: ["model": model, "source": "ModelPickerViewModel"]
                    )
                }
        }
    }
    
    private func fetchOpenRouterModels() async -> [ModelSource] {
        guard let url = URL(string: "https://openrouter.ai/api/v1/models") else { return [] }
        let defaultVaultPath = PathConfiguration.shared.vaultURL
        guard let vault = try? VaultManager(configURL: defaultVaultPath),
              let providerConf = vault.config.providers.first(where: { $0.id == "openrouter" }),
              let apiKey = try? await vault.getAPIKey(for: providerConf) else {
            return []
        }
        
        var request = URLRequest(url: url)
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("https://eliteagent.app", forHTTPHeaderField: "HTTP-Referer")
        request.setValue("EliteAgent/1.0", forHTTPHeaderField: "X-Title")
        
        guard let (data, _) = try? await URLSession.shared.data(for: request) else { return [] }
        
        struct ORResponse: Codable {
            struct ORModel: Codable {
                let id: String
                let name: String
                struct Pricing: Codable { let prompt: String; let completion: String }
                let pricing: Pricing
                let context_length: Int?
            }
            let data: [ORModel]
        }
        
        guard let decoded = try? JSONDecoder().decode(ORResponse.self, from: data) else { return [] }
        
        return decoded.data
            .sorted { $0.name.lowercased() < $1.name.lowercased() }
            .map { model in
            .openRouter(
                id: model.id,
                name: model.name,
                isFree: model.pricing.prompt == "0",
                contextK: (model.context_length ?? 0) / 1000,
                promptPrice: Decimal(string: model.pricing.prompt),
                completionPrice: Decimal(string: model.pricing.completion)
            )
        }
    }
}
