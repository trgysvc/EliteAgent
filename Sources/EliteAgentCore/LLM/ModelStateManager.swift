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
    
    private init() {
        // Default to local Qwen 2.5 7B as base state
        let defaultModel = "qwen-2.5-7b-4bit"
        self.activeProvider = .localTitanEngine(modelID: defaultModel)
        self.currentModelID = defaultModel
        
        // Sync with legacy selected model if exists
        if let saved = UserDefaults.standard.string(forKey: "elite.ai.selectedModel") {
            self.currentModelID = saved
            self.activeProvider = .localTitanEngine(modelID: saved)
        }
    }
    
    /// Switches the system to Cloud mode due to local failure/stress.
    public func switchToCloud(reason: String) async {
        self.isCloudFallback = true
        self.fallbackReason = reason
        
        // Priority: Gemini 2.0 Flash is the most reliable fallback
        let cloudProvider: ModelProvider = .cloudOpenRouter(modelID: "google/gemini-2.0-flash-001")
        self.activeProvider = cloudProvider
        
        // v9.9: Atomic sync to legacy AISessionState for compatibility
        AISessionState.shared.isFallbackActive = true
        AISessionState.shared.activeProvider = "bulut"
        AISessionState.shared.fallbackReason = reason
        
        // Show notification with Undo option via NotificationCenter
        NotificationCenter.default.post(
            name: NSNotification.Name("app.eliteagent.autoFallbackTriggered"),
            object: nil,
            userInfo: ["message": "☁️ Cloud Mode Aktif (\(reason))"]
        )
        
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
        
        // v9.9: Update legacy state
        AISessionState.shared.isFallbackActive = false
        AISessionState.shared.selectedModel = modelID
        AISessionState.shared.activeProvider = "local"
        
        AgentLogger.logAudit(level: .info, agent: "MODEL_STATE", message: "Successfully returned to LOCAL model: \(modelID)")
    }
}
