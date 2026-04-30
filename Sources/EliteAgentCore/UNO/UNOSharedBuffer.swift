import Foundation

/// v7.0 Stability: UNO Pointer Migration (Zero-Copy)
/// Provides a mechanism to transfer large data blocks between processes 
/// via shared memory handles instead of binary copying.
public final class UNOSharedBuffer: @unchecked Sendable {
    public let fileHandle: FileHandle
    public let size: Int
    private let pointer: UnsafeMutableRawPointer
    
    public init(size: Int) throws {
        self.size = size
        
        // Create an anonymous shared memory segment using a temporary file workaround for Swift 6
        let tempPath = (NSTemporaryDirectory() as NSString).appendingPathComponent("uno-\(UUID().uuidString)")
        let fd = open(tempPath, O_RDWR | O_CREAT | O_EXCL, S_IRUSR | S_IWUSR)
        unlink(tempPath) // Unlink immediately so it's truly anonymous and cleaned up on close
        
        guard fd >= 0 else {
            throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno), userInfo: nil)
        }
        
        // Set the size
        ftruncate(fd, off_t(size))
        
        // Map into local address space
        self.pointer = mmap(nil, size, PROT_READ | PROT_WRITE, MAP_SHARED, fd, 0)
        guard pointer != MAP_FAILED else {
            close(fd)
            throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno), userInfo: nil)
        }
        
        self.fileHandle = FileHandle(fileDescriptor: fd, closeOnDealloc: true)
        AgentLogger.logInfo("[UNO-Pointer] Shared buffer created: \(size) bytes.")
    }
    
    /// Returns a pointer for writing to the shared memory.
    public func contents() -> UnsafeMutableRawPointer {
        return pointer
    }
    
    deinit {
        munmap(pointer, size)
    }
}
