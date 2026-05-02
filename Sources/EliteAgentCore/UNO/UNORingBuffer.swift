import Foundation

// C bridge: CUNOSupport target provides the C atomic ring-buffer header and helpers.
// `canImport` guard + lightweight Swift fallbacks allow editors/SourceKit to open this
// file even when the C module isn't visible to the current tooling session.
#if canImport(CUNOSupport)
import CUNOSupport
#else
// Fallback stubs for IDE/editor contexts where the C module isn't available.
// These definitions are intentionally no-op and only exist to avoid "No such module"
// diagnostics. The real C implementations are used when building the package.
public struct UNORingBufferHeader {}

@inlinable public func uno_ring_buffer_init(_ header: UnsafeMutablePointer<UNORingBufferHeader>?, _ capacity: UInt32) {
    // no-op fallback
}

@inlinable public func uno_ring_buffer_get_head(_ header: UnsafeMutablePointer<UNORingBufferHeader>?) -> UInt32 { 0 }

@inlinable public func uno_ring_buffer_set_head(_ header: UnsafeMutablePointer<UNORingBufferHeader>?, _ val: UInt32) {}

@inlinable public func uno_ring_buffer_get_tail(_ header: UnsafeMutablePointer<UNORingBufferHeader>?) -> UInt32 { 0 }

@inlinable public func uno_ring_buffer_set_tail(_ header: UnsafeMutablePointer<UNORingBufferHeader>?, _ val: UInt32) {}
#endif

/// v7.1: Lock-Free Ring Buffer Controller (UNO-RB)
/// streams inference tokens from the MLX Engine (Producer) to the XPC Client (Consumer)
/// using zero-copy memory transfers.
public final class UNORingBuffer: @unchecked Sendable {
    private let header: UnsafeMutablePointer<UNORingBufferHeader>
    private let capacity: UInt32
    
    /// Initializes the controller by binding raw memory to the C-Atomic header.
    /// - Parameter pointer: Raw pointer to the shared memory segment.
    /// - Parameter size: Total size of the allocated memory.
    /// - Parameter isNew: Pass `true` when attaching to freshly allocated memory (producer);
    ///                    `false` when attaching to an already-initialized segment (consumer).
    public init(pointer: UnsafeMutableRawPointer, size: Int, isNew: Bool = true) {
        self.header = pointer.bindMemory(to: UNORingBufferHeader.self, capacity: 1)
        let headerSize = MemoryLayout<UNORingBufferHeader>.stride
        self.capacity = UInt32(size - headerSize)
        if isNew {
            uno_ring_buffer_init(header, capacity)
        }
    }
    
    // MARK: - Consumer Logic (EliteAgent)
    
    /// Reads available data from the buffer without blocking.
    /// - Returns: Data object containing the newly available bytes, if any.
    public func readAvailableData() -> Data? {
        let head = uno_ring_buffer_get_head(header)
        let tail = uno_ring_buffer_get_tail(header)
        
        guard head != tail else { return nil }
        
        var data = Data()
        let dataStart = UnsafeRawPointer(header).advanced(by: MemoryLayout<UNORingBufferHeader>.stride)
        
        if head < tail {
            // Contiguous data
            let len = tail - head
            data.append(dataStart.advanced(by: Int(head)).bindMemory(to: UInt8.self, capacity: Int(len)), count: Int(len))
        } else {
            // Wrapped data
            let firstPart = capacity - head
            data.append(dataStart.advanced(by: Int(head)).bindMemory(to: UInt8.self, capacity: Int(firstPart)), count: Int(firstPart))
            data.append(dataStart.bindMemory(to: UInt8.self, capacity: Int(tail)), count: Int(tail))
        }
        
        // Update head to signal data has been consumed
        uno_ring_buffer_set_head(header, tail)
        return data
    }
    
    // MARK: - Producer Logic (MLX Engine)
    
    /// Writes data to the buffer with native backpressure.
    /// - Parameter data: The data to write (inference tokens).
    public func writeWithBackpressure(data: Data) async throws {
        let writeSize = UInt32(data.count)
        guard writeSize < capacity else {
            throw NSError(domain: "UNORingBuffer", code: 413, userInfo: [NSLocalizedDescriptionKey: "Data too large for buffer capacity"])
        }
        
        var written = false
        while !written {
            try Task.checkCancellation()
            
            let head = uno_ring_buffer_get_head(header)
            let tail = uno_ring_buffer_get_tail(header)
            
            let availableSpace: UInt32
            if tail >= head {
                availableSpace = (capacity - tail + head) - 1
            } else {
                availableSpace = head - tail - 1
            }
            
            if availableSpace >= writeSize {
                let dataStart = UnsafeMutableRawPointer(header).advanced(by: MemoryLayout<UNORingBufferHeader>.stride)
                
                data.withUnsafeBytes { buffer in
                    if let baseAddress = buffer.baseAddress {
                        if tail + writeSize <= capacity {
                            // Contiguous write
                            dataStart.advanced(by: Int(tail)).copyMemory(from: baseAddress, byteCount: Int(writeSize))
                            uno_ring_buffer_set_tail(header, (tail + writeSize) % capacity)
                        } else {
                            // Wrapped write
                            let firstPart = capacity - tail
                            let secondPart = writeSize - firstPart
                            dataStart.advanced(by: Int(tail)).copyMemory(from: baseAddress, byteCount: Int(firstPart))
                            dataStart.copyMemory(from: baseAddress.advanced(by: Int(firstPart)), byteCount: Int(secondPart))
                            uno_ring_buffer_set_tail(header, secondPart)
                        }
                    }
                }
                written = true
            } else {
                // BACKPRESSURE: Buffer is full, yield and wait
                AgentLogger.logWarn("[UNO-RB] Buffer full, applying backpressure.")
                await Task.yield()
                // Sleep for 1ms to allow consumer to catch up without pinning the CPU
                try await Task.sleep(nanoseconds: 1_000_000)
            }
        }
    }
}
