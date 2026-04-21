import Foundation
import Observation
import SwiftUI

// v9.9: Bridged with ModelStateManager (Single Source of Truth)
@MainActor
@Observable
public final class AISessionState {
    public static let shared = AISessionState()
    
    // Persistence Keys
    private let selectedModelKey = "elite.ai.selectedModel"
    private let fallbackPolicyKey = "elite.ai.fallbackPolicy"
    
    // UI-Bound Properties (Bridged with ModelStateManager)
    public var selectedModel: String? {
        get { ModelStateManager.shared.currentModelID }
        set { 
            ModelStateManager.shared.currentModelID = newValue
            if let val = newValue {
                UserDefaults.standard.set(val, forKey: selectedModelKey) 
            }
        }
    }
    
    public var activeProvider: String {
        switch ModelStateManager.shared.activeProvider {
        case .none: return "none"
        case .localTitanEngine: return "local"
        case .cloudOpenRouter: return "cloud"
        }
    }
    
    public var isFallbackActive: Bool {
        get { ModelStateManager.shared.isCloudFallback }
        set { ModelStateManager.shared.isCloudFallback = newValue }
    }
    
    public var fallbackReason: String? {
        get { ModelStateManager.shared.fallbackReason }
        set { ModelStateManager.shared.fallbackReason = newValue }
    }

    public var requiresUserAcknowledgement: Bool = false
    public var requiresPermissionAcknowledgement: Bool = false
    public var permissionAppTarget: String? = nil
    public var isInputLocked: Bool = false
    public var isRestartingEngine: Bool = false
    public var isThermalThrottled: Bool = false
    
    public var fallbackPolicy: FallbackPolicy {
        didSet { UserDefaults.standard.set(fallbackPolicy.rawValue, forKey: fallbackPolicyKey) }
    }
    
    // v7.8.5 Observability Metrics
    public var lastInferenceLatency: Double = 0.0
    public var tokensPerSecond: Double = 0.0
    public var fallbackCount: Int {
        get { UserDefaults.standard.integer(forKey: "aisession_fallback_count") }
        set { UserDefaults.standard.set(newValue, forKey: "aisession_fallback_count") }
    }
    
    // v10.0: Local Server Runtime Status
    public var isLocalServerRunning: Bool = false
    
    private init() {
        if let policyRaw = UserDefaults.standard.string(forKey: fallbackPolicyKey),
           let policy = FallbackPolicy(rawValue: policyRaw) {
            self.fallbackPolicy = policy
        } else {
            self.fallbackPolicy = .promptBeforeSwitch
        }
    }
    
    /// Resets inference-specific flags for a new task.
    public func resetForNewTask() {
        self.isFallbackActive = false
        self.fallbackReason = nil
        self.requiresUserAcknowledgement = false
        self.requiresPermissionAcknowledgement = false
        self.permissionAppTarget = nil
        self.isInputLocked = false
        self.isRestartingEngine = false
        self.isThermalThrottled = false
    }
}
