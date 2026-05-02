import os
import Foundation
import CryptoKit

/// v13.7: UNO (Unified Native Orchestration) Transport Layer
/// Stable Type-Safe XPC Bridge for EliteAgent's tool execution.
/// v14.0: Refactored to `actor` — eliminates NSLock + @unchecked Sendable.
@available(macOS 13.0, *)
public actor UNOTransport {
    public static let shared = UNOTransport(serviceName: "com.eliteagent.sandbox")

    private var _connection: NSXPCConnection?
    private let serviceName: String

    public init(serviceName: String) { self.serviceName = serviceName }

    public func executeRemote(action: UNOActionWrapper) async throws -> UNOResponse {
        let conn = try getOrCreateConnection()

        let encoder = PropertyListEncoder()
        encoder.outputFormat = .binary
        let data = try encoder.encode(action)

        let threshold = 64 * 1024 // 64 KB

        if data.count > threshold {
            let (id, safePointer, fileHandle) = try await SharedMemoryPool.shared.allocate(size: data.count)
            safePointer.pointer.copyMemory(from: (data as NSData).bytes, byteCount: data.count)

            let coordinator = try MachPortCoordinator()
            let sendRight = try await coordinator.extractSendRight()
            let machPort = NSMachPort(machPort: sendRight)

            return try await withCheckedThrowingContinuation { continuation in
                Task {
                    await coordinator.startNonBlockingListener {
                        AgentLogger.logInfo("🔔 [UNO-Mach] Signal received. Data is ready in shmem.")
                    }
                }

                let proxy = conn.remoteObjectProxyWithErrorHandler { error in
                    Task { await SharedMemoryPool.shared.release(id: id) }
                    continuation.resume(throwing: error)
                } as? UNORemoteProxy

                proxy?.performMachAction(shmem: fileHandle, size: data.count, signalPort: machPort) { resultData, errorData in
                    Task { await SharedMemoryPool.shared.release(id: id) }
                    self.handleXPCResponse(resultData: resultData, errorData: errorData,
                                           action: action, continuation: continuation)
                }
            }
        }

        return try await withCheckedThrowingContinuation { continuation in
            let proxy = conn.remoteObjectProxyWithErrorHandler { error in
                continuation.resume(throwing: error)
            } as? UNORemoteProxy

            proxy?.performRemoteAction(data: data) { resultData, errorData in
                self.handleXPCResponse(resultData: resultData, errorData: errorData,
                                       action: action, continuation: continuation)
            }
        }
    }

    nonisolated private func handleXPCResponse(resultData: Data?, errorData: Data?,
                                               action: UNOActionWrapper,
                                               continuation: CheckedContinuation<UNOResponse, Error>) {
        if let errorData = errorData {
            let errStr = String(data: errorData, encoding: .utf8) ?? "XPC Error"
            continuation.resume(throwing: NSError(domain: "UNO", code: 500,
                                                  userInfo: [NSLocalizedDescriptionKey: errStr]))
            return
        }

        guard let data = resultData else {
            continuation.resume(throwing: NSError(domain: "UNO", code: 404))
            return
        }

        do {
            let response = try PropertyListDecoder().decode(UNOResponse.self, from: data)
            if response.version != action.version {
                AgentLogger.logAudit(level: .error, agent: "UNO",
                                     message: "Schema Mismatch: Sent V\(action.version), Recv V\(response.version)")
            }
            continuation.resume(returning: response)
        } catch {
            continuation.resume(throwing: error)
        }
    }

    private func getOrCreateConnection() throws -> NSXPCConnection {
        if let existing = _connection { return existing }
        let newConn = NSXPCConnection(serviceName: serviceName)
        newConn.remoteObjectInterface = NSXPCInterface(with: UNORemoteProxy.self)
        newConn.resume()
        _connection = newConn
        return newConn
    }
}

@objc public protocol UNORemoteProxy {
    func performRemoteAction(data: Data, reply: @escaping @Sendable (Data?, Data?) -> Void)
    func performSharedAction(shmem: FileHandle, size: Int, reply: @escaping @Sendable (Data?, Data?) -> Void)
    func performMachAction(shmem: FileHandle, size: Int, signalPort: NSMachPort, reply: @escaping @Sendable (Data?, Data?) -> Void)
}
