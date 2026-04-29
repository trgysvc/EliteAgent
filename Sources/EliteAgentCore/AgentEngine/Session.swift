import Foundation
import AudioIntelligence

// MARK: - Task Progress Tracker

/// Monitors task steps and their completion status.
/// OrchestratorRuntime injects this status into every planning turn,
/// ensuring both the model and the Critic are aware of what has been accomplished.
public actor TaskProgressTracker {

    public struct Step: Sendable {
        public let index: Int
        public let description: String
        public var isCompleted: Bool = false
        public var evidence: String? = nil // Objective proof from Observation
    }

    public private(set) var steps: [Step] = []
    public private(set) var isInitialized: Bool = false

    public init() {}

    /// Registers steps during initial planning (called in the first planning turn).
    public func setSteps(_ descriptions: [String]) {
        guard !isInitialized, !descriptions.isEmpty else { return }
        self.steps = descriptions.enumerated().map {
            Step(index: $0.offset + 1, description: $0.element)
        }
        self.isInitialized = true
    }

    /// Marks a step as completed with objective evidence from a tool observation.
    public func markCompleted(stepIndex: Int, evidence: String) {
        guard stepIndex > 0, stepIndex <= steps.count else { return }
        steps[stepIndex - 1].isCompleted = true
        steps[stepIndex - 1].evidence = String(evidence.prefix(200))
    }

    /// Returns the index of the next uncompleted step.
    public func nextPendingStepIndex() -> Int? {
        steps.first(where: { !$0.isCompleted })?.index
    }

    /// Checks if all registered steps are completed.
    public var allCompleted: Bool {
        isInitialized && !steps.isEmpty && steps.allSatisfy { $0.isCompleted }
    }

    /// Task progress block to be injected into the planning turn.
    public func statusBlock() -> String {
        guard isInitialized else { return "" }
        let lines = steps.map { step -> String in
            let icon = step.isCompleted ? "✅" : "⏳"
            let evidenceNote = step.isCompleted
                ? " [Evidence: \(step.evidence ?? "ok")]"
                : ""
            return "   \(icon) Step \(step.index): \(step.description)\(evidenceNote)"
        }
        let doneCount = steps.filter { $0.isCompleted }.count
        let nextLabel = nextPendingStepIndex()
            .map { "Work on Step \($0)" }
            ?? "All steps completed → output <final>DONE</final>"
        return """
        
        ### 📋 TASK PROGRESS STATUS (\(doneCount)/\(steps.count) completed):
        \(lines.joined(separator: "\n"))
        ⚡ Next: \(nextLabel)
        """
    }
}

// MARK: - Session Status

public enum SessionStatus: String, Codable, Sendable {
    case idle
    case thinking
    case executing
    case verifying
    case finished
    case failed
    case healing
}

// MARK: - Session

public actor Session: Identifiable {
    public let id: UUID
    public let parentID: UUID?
    public let recursionDepth: Int
    public let maxRecursionDepth: Int
    public let workspaceURL: URL
    public let config: InferenceConfig
    public let complexity: Int

    public private(set) var status: SessionStatus = .idle
    public private(set) var promptTokens: Int = 0
    public private(set) var completionTokens: Int = 0
    public private(set) var healingAttempts: Int = 0
    public private(set) var finalAnswer: String?
    public private(set) var wasWidgetRendered: Bool = false

    /// Task step tracker — monitors step count, completion, and objective evidence.
    public let progressTracker = TaskProgressTracker()

    // Music DNA Analysis (Titan Integration)
    public var audioAnalysis: MusicDNAAnalysis?

    // Live feedback stream (Titan Architecture)
    public var onStreamOutput: (@Sendable (String) -> Void)?

    public init(id: UUID = UUID(),
                parentID: UUID? = nil,
                recursionDepth: Int = 0,
                maxRecursionDepth: Int = 5,
                workspaceURL: URL,
                config: InferenceConfig = .default,
                complexity: Int = 1) {
        self.id = id
        self.parentID = parentID
        self.recursionDepth = recursionDepth
        self.maxRecursionDepth = maxRecursionDepth
        self.workspaceURL = workspaceURL
        self.config = config
        self.complexity = complexity
    }

    public func setStreamHandler(_ handler: @Sendable @escaping (String) -> Void) {
        self.onStreamOutput = handler
    }

    public func streamOutput(_ text: String) {
        self.onStreamOutput?(text)
    }

    public func updateStatus(_ newStatus: SessionStatus, finalAnswer: String? = nil) {
        self.status = newStatus
        if let answer = finalAnswer {
            self.finalAnswer = answer
        }
    }

    public func setFinalAnswer(_ content: String) {
        self.updateStatus(.finished, finalAnswer: content)
    }

    public func markWidgetAsRendered() {
        self.wasWidgetRendered = true
    }

    // v24.2: Anti-Repetition Tracking
    private var executedToolSignatures: Set<String> = []
    
    public func hasToolBeenExecuted(signature: String) -> Bool {
        return executedToolSignatures.contains(signature)
    }
    
    public func markToolAsExecuted(signature: String) {
        executedToolSignatures.insert(signature)
    }

    public func setAudioAnalysis(_ analysis: MusicDNAAnalysis) {
        self.audioAnalysis = analysis
    }

    public var totalTokenUsage: Int {
        promptTokens + completionTokens
    }

    public func addTokenUsage(_ count: TokenCount) {
        self.promptTokens += count.prompt
        self.completionTokens += count.completion
    }

    public func recordHealingAttempt() {
        self.healingAttempts += 1
    }

    public func isRecursionLimitReached() -> Bool {
        return recursionDepth >= maxRecursionDepth
    }
}
