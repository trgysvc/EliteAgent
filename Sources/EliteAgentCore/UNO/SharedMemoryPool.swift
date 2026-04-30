import Foundation

public struct UNOSafePointer: @unchecked Sendable {
    public let pointer: UnsafeMutableRawPointer
    public init(_ pointer: UnsafeMutableRawPointer) { self.pointer = pointer }
}

/// v7.0 Stability: UNO Shared Memory Pool
/// Manages the lifecycle of shared memory buffers for zero-copy IPC.
public actor SharedMemoryPool {
    public static let shared = SharedMemoryPool()
    
    private var activeBuffers: [UUID: UNOSharedBuffer] = [:]
    
    private init() {}
    
    /// Allocates a new shared memory buffer and returns its identifier and pointer.
    public func allocate(size: Int) throws -> (UUID, UNOSafePointer, FileHandle) {
        let id = UUID()
        let buffer = try UNOSharedBuffer(size: size)
        activeBuffers[id] = buffer
        
        AgentLogger.logAudit(level: .info, agent: "UNO-Pool", message: "Allocated \(size) bytes (ID: \(id.uuidString.prefix(8)))")
        return (id, UNOSafePointer(buffer.contents()), buffer.fileHandle)
    }
    
    /// Releases a buffer from the pool, triggering deallocation.
    public func release(id: UUID) {
        if activeBuffers.removeValue(forKey: id) != nil {
            AgentLogger.logAudit(level: .info, agent: "UNO-Pool", message: "Released buffer (ID: \(id.uuidString.prefix(8)))")
        }
    }
    
    /// Accesses an active buffer by its UUID.
    public func getBuffer(id: UUID) -> UNOSharedBuffer? {
        return activeBuffers[id]
    }
}
