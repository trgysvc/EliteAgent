import Foundation

public actor ExecutorAgent: AgentProtocol {
    public let agentID: AgentID = .executor
    public private(set) var status: AgentStatus = .idle
    public let preferredProvider: ProviderID = ProviderID(rawValue: "mlx")
    public let fallbackProviders: [ProviderID] = [ProviderID(rawValue: "openrouter")]
    
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
