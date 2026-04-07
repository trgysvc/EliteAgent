import Foundation
import SwiftUI
import Combine

/// Single source of truth for the active model provider and state.
@MainActor
public final class ModelStateManager: ObservableObject {
    public static let shared = ModelStateManager()
    
    @Published public var activeProvider: ModelProvider
    @Published public var isCloudFallback: Bool = false
    @Published var currentModelID: String?
    @Published var fallbackReason: String?
    
    /// v9.9.5: Resilient Self-Healing Mode
    /// Holds the ID of the local model that needs repair/download.
    @Published public var pendingRepairModelID: String?
    
    // v10.5: Throttling & Telemetry
    private let lastWizardPromptKey = "elite.ai.lastWizardPromptDate"
    
    private init() {
        // v10.1: No hardcoded defaults. System is truly data-driven on fresh installs.
        let initialModel: String? = UserDefaults.standard.string(forKey: "elite.ai.selectedModel")
        
        // 1. Validation Logic: Does the selected model actually exist? (Ghost Model Migration)
        let modelID = initialModel
        let filesExist = modelID != nil ? ModelManager.shared.doesModelDirectoryExist(id: modelID!) : false
        let isComplete = modelID != nil ? ModelManager.shared.isModelComplete(id: modelID!) : false
        
        if isComplete, let validID = modelID {
            self.activeProvider = .localTitanEngine(modelID: validID)
            self.currentModelID = validID
            self.isCloudFallback = false
        } else if filesExist && !isComplete, let repairID = modelID {
            self.pendingRepairModelID = repairID
            self.activeProvider = .none
            self.currentModelID = nil
            self.isCloudFallback = false
            self.fallbackReason = "Yerel model dosyaları bozuk (Onarım Gerekli)"
            Task { await UXTelemetryManager.shared.startNoneStateTracking() }
        } else {
            // No model or ghost model -> Reset to clean state
            self.activeProvider = .none
            self.currentModelID = nil
            self.isCloudFallback = false
            self.fallbackReason = "Sistem Hazır Değil: Lütfen bir model kurun."
            
            // v10.5: Cleanup ghost selection from UserDefaults if it was invalid
            if initialModel != nil {
                UserDefaults.standard.removeObject(forKey: "elite.ai.selectedModel")
                AgentLogger.logInfo("ModelStateManager: Ghost model '\(initialModel!)' detected and cleared.")
            }
            
            Task { 
                await UXTelemetryManager.shared.startNoneStateTracking()
                await self.triggerWizardIfNeeded()
            }
        }
    }
    
    /// v10.5: Throttled wizard trigger to avoid annoying the user.
    private func triggerWizardIfNeeded() async {
        let lastPrompt = UserDefaults.standard.object(forKey: lastWizardPromptKey) as? Date ?? .distantPast
        let now = Date()
        
        // Only prompt once every 24 hours (86,400 seconds)
        if now.timeIntervalSince(lastPrompt) > (24 * 3600) {
            UserDefaults.standard.set(now, forKey: lastWizardPromptKey)
            
            await MainActor.run {
                NotificationCenter.default.post(name: Notification.Name.openModelSetup, object: nil)
                AgentLogger.logInfo("ModelStateManager: Wizard auto-triggered (Throttled).")
            }
            
            await UXTelemetryManager.shared.recordWizardInteraction(action: "wizard_auto_triggered")
        }
    }
    
    /// User action to confirm repair strategy - v9.9.5
    public func confirmRepairAndContinue(useCloudInMeantime: Bool) async {
        guard let modelID = pendingRepairModelID else { return }
        
        AgentLogger.logInfo("Initializing resilient repair for \(modelID)...")
        
        // 1. Kick off background download
        if let catalog = ModelRegistry.availableModels.first(where: { $0.id == modelID }) {
            Task { try? await ModelManager.shared.download(catalog) }
        }
        
        // 2. Adjust active provider based on choice
        if useCloudInMeantime {
            // Already in cloud fallback state, just keep it
            AgentLogger.logInfo("Continuity Mode: Streaming via Cloud while repairing \(modelID).")
        }
        
        // Clear pending flag so the dialog dismisses
        withAnimation { self.pendingRepairModelID = nil }
    }
    
    /// Switches the system to Cloud mode due to local failure/stress.
    public func switchToCloud(reason: String) async {
        self.isCloudFallback = true
        self.fallbackReason = reason
        
        // Priority: Gemini 2.0 Flash is the most reliable fallback
        let cloudProvider: ModelProvider = .cloudOpenRouter(modelID: "google/gemini-2.0-flash-001")
        self.activeProvider = cloudProvider
        
        AISessionState.shared.isFallbackActive = true
        AISessionState.shared.fallbackReason = reason
        
        await UXTelemetryManager.shared.stopNoneStateTracking()
        
        // Show notification with Undo option via NotificationCenter
        DispatchQueue.main.async {
            NotificationCenter.default.post(
                name: NSNotification.Name("app.eliteagent.autoFallbackTriggered"),
                object: nil,
                userInfo: ["message": "☁️ Cloud Mode Aktif (\(reason))"]
            )
        }
        
        AgentLogger.logAudit(level: .warn, agent: "MODEL_STATE", message: "Successfully transitioned to CLOUD fallback: \(reason)")
    }
    
    /// Switches back to a specific local model.
    public func switchToLocal(_ modelID: String) async throws {
        self.isCloudFallback = false
        self.fallbackReason = nil
        
        // Ensure model is loaded in the inference container (auto-prime)
        // v9.9: ModelManager handles the technical loading/priming check
        try await ModelManager.shared.load(modelID)
        
        self.activeProvider = .localTitanEngine(modelID: modelID)
        self.currentModelID = modelID
        
        await UXTelemetryManager.shared.stopNoneStateTracking()
        
        DispatchQueue.main.async {
            AISessionState.shared.isFallbackActive = false
            AISessionState.shared.selectedModel = modelID
        }
        
        AgentLogger.logAudit(level: .info, agent: "MODEL_STATE", message: "Successfully returned to LOCAL model: \(modelID)")
    }
}
