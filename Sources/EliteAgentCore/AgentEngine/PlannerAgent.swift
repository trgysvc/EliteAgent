import Foundation
import Combine

public actor PlannerAgent: AgentProtocol {
    public let agentID: AgentID = .planner
    public private(set) var status: AgentStatus = .idle
    public let preferredProvider: ProviderID = .mlx
    public let fallbackProviders: [ProviderID] = [.openrouter]
    
    private let bus: SignalBus
    private var lastUserInput: String?
    
    public init(bus: SignalBus) {
        self.bus = bus
    }
    
    public func receive(_ signal: Signal) async throws {
        if signal.name == "USER_INPUT" {
            let input = String(data: signal.payload, encoding: .utf8) ?? ""
            self.lastUserInput = input
            AgentLogger.logAudit(level: .info, agent: "PlannerAgent", message: "Received USER_INPUT for clarification.")
        }
    }
    
    public func popLastInput() -> String? {
        let input = lastUserInput
        lastUserInput = nil
        return input
    }
    
    public func healthReport() -> AgentHealth {
        return AgentHealth(isHealthy: true, statusMessage: "OK")
    }
}
