import Foundation
import Darwin.Mach

/// v7.2: Native Mach Port Coordinator (Zero-Latency Signaling)
/// Manages shared memory synchronization between the Titan Engine and XPC Client
/// using native Mach port events with Swift Concurrency (no DispatchSource).
public final actor MachPortCoordinator {
    private let receivePort: mach_port_t
    private var listenerTask: Task<Void, Never>?

    public init() throws {
        var newPort: mach_port_t = 0
        let kr = mach_port_allocate(mach_task_self_, MACH_PORT_RIGHT_RECEIVE, &newPort)

        guard kr == KERN_SUCCESS else {
            throw NSError(domain: NSMachErrorDomain, code: Int(kr),
                          userInfo: [NSLocalizedDescriptionKey: "Mach port allocation failed"])
        }
        self.receivePort = newPort
        AgentLogger.logAudit(level: .info, agent: "UNO-Mach",
                             message: "Allocated Mach receive port: \(newPort)")
    }

    /// Extracts a send-right (write permission) to be transferred via XPC.
    public func extractSendRight() throws -> mach_port_t {
        let kr = mach_port_insert_right(mach_task_self_, receivePort, receivePort,
                                        mach_msg_type_name_t(MACH_MSG_TYPE_MAKE_SEND))
        guard kr == KERN_SUCCESS else {
            throw NSError(domain: NSMachErrorDomain, code: Int(kr),
                          userInfo: [NSLocalizedDescriptionKey: "Failed to insert Mach send right"])
        }
        return receivePort
    }

    /// Starts an async listener that delivers a single notification when a Mach message arrives.
    /// Bridges the kernel event into Swift Concurrency via a checked continuation.
    public func startNonBlockingListener(onDataReady: @escaping @Sendable () -> Void) {
        listenerTask?.cancel()
        let port = receivePort
        listenerTask = Task.detached(priority: .high) {
            await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
                // Block the detached thread until a Mach message arrives.
                var header = mach_msg_header_t()
                let kr = mach_msg(&header,
                                  MACH_RCV_MSG,
                                  0,
                                  UInt32(MemoryLayout<mach_msg_header_t>.size),
                                  port,
                                  MACH_MSG_TIMEOUT_NONE,
                                  mach_port_name_t(MACH_PORT_NULL))
                if kr == MACH_MSG_SUCCESS {
                    continuation.resume()
                } else {
                    AgentLogger.logError("[UNO-Mach] mach_msg receive failed: \(kr)")
                    continuation.resume()
                }
            }
            onDataReady()
        }
        AgentLogger.logInfo("[UNO-Mach] Async listener started.")
    }

    deinit {
        listenerTask?.cancel()
        mach_port_deallocate(mach_task_self_, receivePort)
    }
}

/// v7.2: Mach Signaling Helper (Server Side)
public struct MachSignaler {
    /// Sends a lightweight signal to the specified Mach port.
    public static func signal(port: mach_port_t) {
        var header = mach_msg_header_t()
        header.msgh_bits = UInt32(MACH_MSG_TYPE_COPY_SEND)
        header.msgh_size = UInt32(MemoryLayout<mach_msg_header_t>.size)
        header.msgh_remote_port = port
        header.msgh_local_port = mach_port_t(MACH_PORT_NULL)
        header.msgh_id = 0

        let kr = mach_msg_send(&header)
        if kr != MACH_MSG_SUCCESS {
            AgentLogger.logError("[UNO-Mach] Mach signal failed: \(kr)")
        }
    }
}
