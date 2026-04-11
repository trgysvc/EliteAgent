import Foundation

/// Temel Ajan Protokolü (MADDE 5.2)
public protocol AgentProtocol: Actor {
    var agentID: AgentID { get }
    var status: AgentStatus { get }
    var preferredProvider: ProviderID { get }
    var fallbackProviders: [ProviderID] { get }

    /// Sinyal alır ve işler
    func receive(_ signal: Signal) async throws
    
    /// Durum raporu döner
    func healthReport() -> AgentHealth
}
