import Foundation
import CryptoKit

/// The SignalBus is the central nervous system of EliteAgent.
/// It implements a prioritized, point-to-point and broadcast signaling mechanism.
public actor SignalBus {
    private var standardContinuations: [AgentID: [AsyncStream<Signal>.Continuation]] = [:]
    private var emergencyContinuations: [AgentID: [AsyncStream<Signal>.Continuation]] = [:]
    private let secretKey: SymmetricKey
    public let sharedSecret: SymmetricKey
    
    public init(secretKey: SymmetricKey) {
        self.secretKey = secretKey
        self.sharedSecret = secretKey
    }
    
    public func dispatch(_ signal: Signal) throws {
        try publish(signal)
    }

    /// Convenience method for posting simple signals.
    public func post(name: String, source: AgentID = .orchestrator, target: AgentID = .orchestrator, priority: SignalPriority = .normal, payload: Data = Data()) throws {
        let signal = Signal(
            source: source,
            target: target,
            name: name,
            priority: priority,
            payload: payload,
            secretKey: self.sharedSecret
        )
        try publish(signal)
    }

    public func publish(_ signal: Signal) throws {
        guard signal.verifySignature(using: secretKey) else {
            print("[ERROR] SignalBus: Invalid signal signature from \(signal.source)")
            throw SignalError.invalidDirection(source: signal.source, target: signal.target) // Using existing case as fallback
        }
        
        let target = signal.target
        let isEmergency = (signal.priority == .critical || signal.priority == .high)
        
        // Route to specific agent or broadcast
        if target == .orchestrator && isEmergency == false {
             // Routine orchestrator messages
        }
        
        notifySubscribers(for: target, signal: signal, isEmergency: isEmergency)
    }
    
    private func notifySubscribers(for agent: AgentID, signal: Signal, isEmergency: Bool) {
        let registry = isEmergency ? emergencyContinuations : standardContinuations
        
        // Targeted delivery
        if let agentContinuations = registry[agent] {
            for continuation in agentContinuations {
                continuation.yield(signal)
            }
        }
        
        // Broadcasts (if we implement a broadcast ID, for now we can use a special case or just send to all)
    }
    
    /// Subscribes an agent to its prioritized signal streams.
    /// - Returns: A tuple of (emergencyStream, standardStream)
    public func subscribe(for agent: AgentID) -> (emergency: AsyncStream<Signal>, standard: AsyncStream<Signal>) {
        let (emergencyStream, emergencyContinuation) = AsyncStream<Signal>.makeStream()
        let (standardStream, standardContinuation) = AsyncStream<Signal>.makeStream()
        
        emergencyContinuations[agent, default: []].append(emergencyContinuation)
        standardContinuations[agent, default: []].append(standardContinuation)
        
        return (emergencyStream, standardStream)
    }
}
