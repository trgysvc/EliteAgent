import Foundation
import CryptoKit

/// v13.6: UNO (Unified Native Orchestration) Transport Layer
/// Stable Type-Safe XPC Bridge for EliteAgent's tool execution.
@available(macOS 13.0, *)
public final class UNOTransport: @unchecked Sendable {
    public static let shared = UNOTransport(serviceName: "com.eliteagent.sandbox")
    
    private let lock = NSLock()
    private var connection: NSXPCConnection?
    private let serviceName: String
    
    public init(serviceName: String) { self.serviceName = serviceName }
    
    public func executeRemote(action: UNOActionWrapper) async throws -> UNOResponse {
        let conn = try getOrCreateConnection()
        let data = try JSONEncoder().encode(action)
        
        return try await withCheckedThrowingContinuation { continuation in
            let proxy = conn.remoteObjectProxyWithErrorHandler { error in
                continuation.resume(throwing: error)
            } as? UNORemoteProxy
            
            guard let safeProxy = proxy else {
                continuation.resume(throwing: NSError(domain: "UNO", code: 500, userInfo: [NSLocalizedDescriptionKey: "Proxy failed"]))
                return
            }
            
            safeProxy.performRemoteAction(data: data) { resultData, errorData in
                if let errorData = errorData {
                    let errStr = String(data: errorData, encoding: .utf8) ?? "XPC Error"
                    continuation.resume(throwing: NSError(domain: "UNO", code: 500, userInfo: [NSLocalizedDescriptionKey: errStr]))
                    return
                }
                
                guard let data = resultData else {
                    continuation.resume(throwing: NSError(domain: "UNO", code: 404))
                    return
                }
                
                do {
                    let response = try JSONDecoder().decode(UNOResponse.self, from: data)
                    continuation.resume(returning: response)
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    private func getOrCreateConnection() throws -> NSXPCConnection {
        lock.lock(); defer { lock.unlock() }
        if let conn = connection { return conn }
        let conn = NSXPCConnection(serviceName: serviceName)
        conn.remoteObjectInterface = NSXPCInterface(with: UNORemoteProxy.self)
        conn.resume()
        self.connection = conn; return conn
    }
}

@objc public protocol UNORemoteProxy {
    func performRemoteAction(data: Data, reply: @escaping @Sendable (Data?, Data?) -> Void)
}
