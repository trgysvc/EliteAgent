import Foundation
import Observation
import SwiftUI

/// Centralized state management for the EliteAgent inference engine and UI.
@MainActor
@Observable
public final class AISessionState {
    public static let shared = AISessionState()
    
    // Persistence Keys
    private let selectedModelKey = "elite.ai.selectedModel"
    private let fallbackPolicyKey = "elite.ai.fallbackPolicy"
    
    // UI-Bound Properties
    public var selectedModel: String {
        didSet { UserDefaults.standard.set(selectedModel, forKey: selectedModelKey) }
    }
    public var activeProvider: String = "local"
    public var isFallbackActive: Bool = false
    public var fallbackReason: String? = nil
    public var requiresUserAcknowledgement: Bool = false
    public var isInputLocked: Bool = false
    
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
    
    private init() {
        var model = UserDefaults.standard.string(forKey: selectedModelKey) ?? "Qwen2.5-7B-Instruct-4bit"
        
        // v7.8.6 Migration: Unify IDs (Instruct variant was renamed for disk consistency)
        if model == "Qwen3.5-9B-Instruct-4bit" {
            model = "Qwen3.5-9B-4bit"
            UserDefaults.standard.set(model, forKey: selectedModelKey)
        }
        
        self.selectedModel = model
        
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
        self.isInputLocked = false
    }
}
