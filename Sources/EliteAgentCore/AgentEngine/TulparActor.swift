import Foundation
import SwiftUI

/// A lightweight state machine for the "Tulpar" Mythology Buddy.
/// Part of the EliteAgent v10.0 "Titan" architecture.
/// This actor is independent of @MainActor to prevent thread blocking.
public actor TulparActor: Sendable {
    public static let shared = TulparActor()
    
    public enum TulparState: String, Sendable {
        case resting   = "💤" // Idle
        case energetic = "🐎" // Success streak > 3
        case thinking  = "🔮" // LLM is working
        case proud     = "✨" // Just completed a task
        case focused   = "🔍" // Researching
    }
    
    private var currentState: TulparState = .resting
    private var successStreak: Int = 0
    
    private init() {}
    
    /// Updates the state based on external events (e.g. task completion).
    public func recordEvent(_ event: AgentEvent) {
        switch event {
        case .taskStarted:
            currentState = .thinking
        case .taskCompleted(let success):
            if success {
                successStreak += 1
                currentState = successStreak > 3 ? .energetic : .proud
            } else {
                successStreak = 0
                currentState = .resting
            }
        case .researchStarted:
            currentState = .focused
        }
    }
    
    public func getCurrentState() -> TulparState {
        return currentState
    }
    
    /// Returns the ASCII representation of the current state.
    /// In a full implementation, this could return complex multiline ASCII art.
    public func getASCIIArt() -> String {
        switch currentState {
        case .resting:
            return """
               (\\
               (  \\  💤
                )  )
               /  /
            """
        case .energetic:
            return """
                 \\/_
                 /  \\  🐎 ✨
                /    \\
            """
        case .thinking:
            return """
               [ 🔮 ]
               ( - - )
               (  V  )
            """
        case .proud:
            return """
               (\\__/ )
               (  ^.^ )  ✨
               (     )
            """
        case .focused:
            return """
               🔍 [Tulpar]
               (  o.o  )
                (  V  )
            """
        }
    }
}

public enum AgentEvent: Sendable {
    case taskStarted
    case taskCompleted(success: Bool)
    case researchStarted
}
