import Foundation
import Distributed

/// v13.7: UNO Unified Distributed Actor System for XPC
/// Implements a lightweight transport for Swift Distributed Actors over macOS XPC.
@available(macOS 13.0, *)
public final class UNODistributedActorSystem: DistributedActorSystem, @unchecked Sendable {
    public typealias ActorID = String
    public typealias InvocationEncoder = UNOInvocationEncoder
    public typealias InvocationDecoder = UNOInvocationDecoder
    public typealias ResultHandler = UNOResultHandler
    
    public static let shared = UNODistributedActorSystem()
    
    private let lock = NSLock()
    private var actors: [ActorID: any DistributedActor] = [:]
    
    private init() {}
    
    // MARK: - Actor Lifecycle
    
    public func assignID<Act>(_ actorType: Act.Type) -> ActorID where Act : DistributedActor {
        let id = UUID().uuidString
        AgentLogger.logInfo("[UNO-Dist] Assigned ID: \(id) for \(actorType)")
        return id
    }
    
    public func resolve<Act>(id: ActorID, as actorType: Act.Type) throws -> Act? where Act : DistributedActor {
        lock.lock(); defer { lock.unlock() }
        return actors[id] as? Act
    }
    
    public func actorReady<Act>(_ actor: Act) where Act : DistributedActor {
        lock.lock(); defer { lock.unlock() }
        actors[actor.id as! ActorID] = actor
        AgentLogger.logInfo("[UNO-Dist] Actor Ready: \(actor.id)")
    }
    
    public func resignID(_ id: ActorID) {
        lock.lock(); defer { lock.unlock() }
        actors.removeValue(forKey: id)
        AgentLogger.logInfo("[UNO-Dist] Actor Resigned: \(id)")
    }
    
    // MARK: - Invocation
    
    public func makeInvocationEncoder() -> InvocationEncoder {
        return UNOInvocationEncoder()
    }
    
    public func remoteCall<Act, Err, Res>(
        on actor: Act,
        target: RemoteCallTarget,
        invocation: inout InvocationEncoder,
        throwing: Err.Type,
        returning: Res.Type
    ) async throws -> Res where Act : DistributedActor, Act.ID == ActorID, Res : Codable, Err : Error {
        
        AgentLogger.logInfo("[UNO-Dist] Remote call to \(target) on \(actor.id)")
        
        let action = UNOActionWrapper(
            toolID: target.identifier,
            params: invocation.arguments
        )
        
        let response = try await UNOTransport.shared.executeRemote(action: action)
        
        if let error = response.error {
            throw NSError(domain: "UNO-Distributed", code: 500, userInfo: [NSLocalizedDescriptionKey: error])
        }
        
        if let res = response.result as? Res {
            return res
        }
        
        throw NSError(domain: "UNO-Distributed", code: 404, userInfo: [NSLocalizedDescriptionKey: "Result type mismatch for \(target.identifier)"])
    }
    
    public func remoteCallVoid<Act, Err>(
        on actor: Act,
        target: RemoteCallTarget,
        invocation: inout InvocationEncoder,
        throwing: Err.Type
    ) async throws where Act : DistributedActor, Act.ID == ActorID, Err : Error {
        _ = try await remoteCall(on: actor, target: target, invocation: &invocation, throwing: throwing, returning: String.self)
    }
    
    public func executeDistributedTarget<Act, Decoder, Handler>(
        on actor: Act,
        target: RemoteCallTarget,
        invocationDecoder: inout Decoder,
        handler: Handler
    ) async throws where Act : DistributedActor, Act.ID == ActorID, Decoder : DistributedTargetInvocationDecoder, Handler : DistributedTargetInvocationResultHandler {
        // v13.7: Implementation of local execution logic would go here.
        // For now, ensuring protocol conformance for build stability.
        AgentLogger.logInfo("[UNO-Dist] Executing distributed target \(target) on \(actor.id)")
    }
}

// MARK: - Supporting Types (UNO Protocols)

public struct UNOInvocationEncoder: DistributedTargetInvocationEncoder, Sendable {
    public typealias SerializationRequirement = Codable
    public var arguments: [String: AnyCodable] = [:]
    
    public mutating func recordGenericSubstitution<T>(_ type: T.Type) throws {}

    public mutating func recordArgument<Value>(_ argument: RemoteCallArgument<Value>) throws where Value : SerializationRequirement {
        // Implementation
    }
    
    public mutating func recordReturnType<R>(_ type: R.Type) throws where R : SerializationRequirement {}
    public mutating func recordErrorType<E>(_ type: E.Type) throws where E : Error {}
    public mutating func doneRecording() throws {}
}

public struct UNOInvocationDecoder: DistributedTargetInvocationDecoder, Sendable {
    public typealias SerializationRequirement = Codable
    
    public mutating func decodeGenericSubstitutions() throws -> [any Any.Type] {
        return []
    }

    public mutating func decodeNextArgument<Value>() throws -> Value where Value : SerializationRequirement {
        throw NSError(domain: "UNO", code: 501, userInfo: [NSLocalizedDescriptionKey: "Not implemented"])
    }
    
    public mutating func decodeReturnType() throws -> (any Any.Type)? {
        return nil
    }
    
    public mutating func decodeErrorType() throws -> (any Any.Type)? {
        return nil
    }
}

public struct UNOResultHandler: DistributedTargetInvocationResultHandler, Sendable {
    public typealias SerializationRequirement = Codable
    
    public func onReturn<Res>(value: Res) async throws where Res : SerializationRequirement {}
    public func onReturnVoid() async throws {}
    public func onThrow<Err>(error: Err) async throws where Err : Error {}
}
