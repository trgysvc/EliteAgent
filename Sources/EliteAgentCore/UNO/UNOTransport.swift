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
        
        let encoder = PropertyListEncoder()
        encoder.outputFormat = .binary
        let data = try encoder.encode(action)
        
        // v7.0: Pointer-Native Migration (Zero-Copy for large payloads)
        // If data > 1MB, use shared memory to avoid XPC copy overhead.
        if data.count > 1024 * 1024 {
            let sharedBuffer = try UNOSharedBuffer(size: data.count)
            sharedBuffer.contents().copyMemory(from: (data as NSData).bytes, byteCount: data.count)
            
            return try await withCheckedThrowingContinuation { continuation in
                let proxy = conn.remoteObjectProxyWithErrorHandler { error in
                    continuation.resume(throwing: error)
                } as? UNORemoteProxy
                
                proxy?.performSharedAction(shmem: sharedBuffer.fileHandle, size: data.count) { resultData, errorData in
                    self.handleXPCResponse(resultData: resultData, errorData: errorData, action: action, continuation: continuation)
                }
            }
        }
        
        return try await withCheckedThrowingContinuation { continuation in
            let proxy = conn.remoteObjectProxyWithErrorHandler { error in
                continuation.resume(throwing: error)
            } as? UNORemoteProxy
            
            proxy?.performRemoteAction(data: data) { resultData, errorData in
                self.handleXPCResponse(resultData: resultData, errorData: errorData, action: action, continuation: continuation)
            }
        }
    }

    private func handleXPCResponse(resultData: Data?, errorData: Data?, action: UNOActionWrapper, continuation: CheckedContinuation<UNOResponse, Error>) {
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
            let response = try PropertyListDecoder().decode(UNOResponse.self, from: data)
            if response.version != action.version {
                AgentLogger.logAudit(level: .error, agent: "UNO", message: "Schema Mismatch: Sent V\(action.version), Recv V\(response.version)")
            }
            continuation.resume(returning: response)
        } catch {
            continuation.resume(throwing: error)
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
    func performSharedAction(shmem: FileHandle, size: Int, reply: @escaping @Sendable (Data?, Data?) -> Void)
}
