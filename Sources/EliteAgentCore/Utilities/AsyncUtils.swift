import Foundation

/// Executes an operation that provides a result via a continuation, with a mandatory timeout.
public func withTimeout<T: Sendable>(seconds: TimeInterval, operation: @Sendable @escaping (CheckedContinuation<T, Error>) -> Void) async throws -> T {
    try await withThrowingTaskGroup(of: T.self) { group in
        // Task 1: The actual operation
        group.addTask {
            try await withCheckedThrowingContinuation { continuation in
                operation(continuation)
            }
        }
        
        // Task 2: The timer
        group.addTask {
            try await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
            throw NSError(
                domain: "com.eliteagent.timeout", 
                code: 408, 
                userInfo: [NSLocalizedDescriptionKey: "İşlem \(Int(seconds)) saniye içerisinde tamamlanamadı (Zaman Aşımı)."]
            )
        }
        
        guard let firstResult = try await group.next() else {
            throw NSError(domain: "com.eliteagent.error", code: 500, userInfo: [NSLocalizedDescriptionKey: "Bilinmeyen hata."])
        }
        
        // Cancel the other task (either the timer if operation finished, or the operation if timer finished)
        group.cancelAll()
        return firstResult
    }
}
