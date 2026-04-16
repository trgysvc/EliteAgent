import Foundation
import SwiftUI

/// Represents the high-level progress of an agent task.
public enum AgentProcessState: Sendable, Equatable {
    case idle
    case uploading(progress: Double)
    case processing(step: ProcessStep)
    case success(result: String)
    case failed(error: String)
}

/// Represents a single step in the agent's reasoning/processing timeline.
public struct ProcessStep: Identifiable, Codable, Sendable, Equatable {
    public enum Status: String, Codable, Sendable {
        case pending
        case active
        case success
        case error
    }
    
    public let id: UUID
    public let name: String
    public let status: Status
    public let icon: String
    
    public init(id: UUID = UUID(), name: String, status: Status, icon: String = "circle") {
        self.id = id
        self.name = name
        self.status = status
        self.icon = icon
    }
    
    public static func step(name: String, status: Status, icon: String = "circle") -> ProcessStep {
        return ProcessStep(name: name, status: status, icon: icon)
    }
}

/// ViewModel to manage the state machine for file uploads and agent processing.
@MainActor
public final class ChatProcessViewModel: ObservableObject {
    @Published public var currentState: AgentProcessState = .idle
    public var onCompletion: ((URL) -> Void)? = nil
    private var processTask: Task<Void, Error>?
    
    public init() {}
    
    /// Starts the file upload and processing pipeline.
    /// - Parameters:
    ///   - fileURL: The URL of the file to process.
    ///   - actor: The InferenceActor instance to handle the task.
    public func startUpload(fileURL: URL, actor: InferenceActor) {
        guard case .idle = currentState else { return }
        
        // HIG Feedback: Immediate state change
        withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
            currentState = .uploading(progress: 0.0)
        }
        
        processTask = Task {
            // 60s Safety Timeout for the entire upload/processing cycle
            let timeoutTask = Task {
                try? await Task.sleep(nanoseconds: 60_000_000_000)
                if !Task.isCancelled {
                    self.cancel(reason: "İşlem zaman aşımına uğradı (60s). Lütfen tekrar deneyin.")
                }
            }
            
            defer { timeoutTask.cancel() }
            
            do {
                // 1. Safe File Reading (mmap)
                let _ = try await readFileSafely(from: fileURL)
                
                // Simulated Upload Progress (Real bytes is better, but this is for UI demo)
                for i in 1...10 {
                    try await Task.sleep(nanoseconds: 100_000_000)
                    if Task.isCancelled { return }
                    withAnimation { currentState = .uploading(progress: Double(i) / 10.0) }
                }
                
                withAnimation {
                    currentState = .success(result: "Yüklendi")
                }
                
                // Signal completion to the UI to trigger main orchestrator task
                onCompletion?(fileURL)
            } catch {
                if !Task.isCancelled {
                    withAnimation {
                        currentState = .failed(error: error.localizedDescription)
                    }
                }
            }
        }
    }
    
    /// Cancels any active process and resets to idle.
    public func cancel(reason: String? = nil) {
        processTask?.cancel()
        withAnimation {
            if let reason = reason {
                currentState = .failed(error: reason)
            } else {
                currentState = .idle
            }
        }
    }
    
    /// Reads file safely using memory-mapped options to prevent RAM spikes.
    private func readFileSafely(from url: URL) async throws -> Data {
        return try await withCheckedThrowingContinuation { continuation in
            // Execute on utility queue to avoid main thread blocking
            DispatchQueue.global(qos: .utility).async {
                autoreleasepool {
                    do {
                        // HIG Recommendation: Use mappedIfSafe for 50MB+ docs
                        let data = try Data(contentsOf: url, options: .mappedIfSafe)
                        continuation.resume(returning: data)
                    } catch {
                        continuation.resume(throwing: error)
                    }
                }
            }
        }
    }
}
