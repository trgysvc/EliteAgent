import Foundation

public actor CriticAgent: AgentProtocol {
    public let agentID: AgentID = .critic
    public private(set) var status: AgentStatus = .idle
    public let preferredProvider: ProviderID = ProviderID(rawValue: "mlx-llama3-8b")
    public let fallbackProviders: [ProviderID] = [ProviderID(rawValue: "mlx-r1-8b")]
    
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
