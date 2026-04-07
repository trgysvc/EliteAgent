import Foundation

/// v9.9.13: SessionContext maintains state across user turns,
/// ensuring model persistence and context-aware tool selection.
public class SessionContext: Codable {
    public var selectedModel: ProviderID
    public var preferredTools: [String]
    public var conversationHistory: [Message]
    public var lastIntent: AgentIntentType?
    
    public init(selectedModel: ProviderID = .mlx, preferredTools: [String] = [], conversationHistory: [Message] = []) {
        self.selectedModel = selectedModel
        self.preferredTools = preferredTools
        self.conversationHistory = conversationHistory
    }
    
    public func updateModel(_ model: ProviderID) {
        self.selectedModel = model
        AgentLogger.logAudit(level: .info, agent: "Session", message: "Model choice persistent: \(model)")
    }
    
    public func addMessage(_ message: Message) {
        self.conversationHistory.append(message)
        // Keep history manageable (last 20 messages)
        if self.conversationHistory.count > 20 {
            self.conversationHistory.removeFirst()
        }
    }
}

public enum AgentIntentType: String, Codable {
    case action
    case research
    case chat
}
