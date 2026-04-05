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
            do {
                // 1. Safe File Reading (mmap)
                let _ = try await readFileSafely(from: fileURL)
                
                // Simulated Upload Progress (Real bytes is better, but this is for UI demo)
                for i in 1...10 {
                    try await Task.sleep(nanoseconds: 100_000_000)
                    if Task.isCancelled { return }
                    withAnimation { currentState = .uploading(progress: Double(i) / 10.0) }
                }
                
                // 2. Integration with Actor Stream
                let streamTask = Task {
                    for await step in await actor.processStream {
                        if Task.isCancelled { break }
                        withAnimation(.easeInOut(duration: 0.3)) {
                            currentState = .processing(step: step)
                        }
                    }
                }
                
                // 3. Execution (v9.2: Pass messages array for context consistency)
                var result = ""
                let prompt = "Analiz et: \(fileURL.lastPathComponent)"
                let messages = [Message(role: "user", content: prompt)]
                
                for await chunk in await actor.generate(messages: messages) {
                    if Task.isCancelled { break }
                    result += chunk
                }
                
                streamTask.cancel()
                
                withAnimation {
                    currentState = .success(result: result)
                }
            } catch {
                withAnimation {
                    currentState = .failed(error: error.localizedDescription)
                }
            }
        }
    }
    
    /// Cancels any active process and resets to idle.
    public func cancel() {
        processTask?.cancel()
        withAnimation {
            currentState = .idle
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
