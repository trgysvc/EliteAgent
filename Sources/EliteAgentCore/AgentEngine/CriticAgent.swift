import Foundation

public actor CriticAgent: AgentProtocol {
    public let agentID: AgentID = .critic
    public private(set) var status: AgentStatus = .idle
    public let preferredProvider: ProviderID = .mlx
    public let fallbackProviders: [ProviderID] = [.openrouter]
    
    private let bus: SignalBus
    
    public init(bus: SignalBus) {
        self.bus = bus
    }
    
    public func receive(_ signal: Signal) async throws {
    }
    
    public func healthReport() -> AgentHealth {
        return AgentHealth(isHealthy: true, statusMessage: "OK")
    }
}
