import Foundation

public enum ChatRole: String, Codable, Sendable {
    case user
    case assistant
}

public struct ChatMessage: Identifiable, Codable, Sendable {
    public let id: UUID
    public let role: ChatRole
    public let content: String
    public let timestamp: Date
    public let isStatus: Bool // v10.1: True if this is a transient status update
    public let audioAnalysis: MusicDNAAnalysis? // Librosa & Forensic data
    
    public init(id: UUID = UUID(), role: ChatRole, content: String, timestamp: Date = Date(), isStatus: Bool = false, audioAnalysis: MusicDNAAnalysis? = nil) {
        self.id = id
        self.role = role
        self.content = content
        self.timestamp = timestamp
        self.isStatus = isStatus
        self.audioAnalysis = audioAnalysis
    }
}

public struct ChatSession: Identifiable, Codable, Sendable {
    public let id: UUID
    public var title: String
    public var messages: [ChatMessage]
    public var steps: [TaskStep]
    public var metadata: SessionMetadata
    public let createdAt: Date
    
    public init(id: UUID = UUID(), title: String, messages: [ChatMessage] = [], steps: [TaskStep] = [], metadata: SessionMetadata = .init(), createdAt: Date = Date()) {
        self.id = id
        self.title = title
        self.messages = messages
        self.steps = steps
        self.metadata = metadata
        self.createdAt = createdAt
    }
}

public struct SessionMetadata: Codable, Sendable {
    public var promptTokens: Int
    public var completionTokens: Int
    public var cost: Decimal
    public var latency: String
    
    public init(promptTokens: Int = 0, completionTokens: Int = 0, cost: Decimal = 0, latency: String = "0s") {
        self.promptTokens = promptTokens
        self.completionTokens = completionTokens
        self.cost = cost
        self.latency = latency
    }
}

// Global actor for serialized disk access
public actor HistoryManager {
    public static let shared = HistoryManager()
    private let fileURL: URL
    
    private init() {
        self.fileURL = PathConfiguration.shared.historyURL
        try? FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
    }
    
    public func save(_ sessions: [ChatSession]) async throws {
        let encoder = PropertyListEncoder()
        encoder.outputFormat = .binary
        let data = try encoder.encode(sessions)
        try data.write(to: fileURL, options: .atomic)
    }
    
    public func load() async throws -> [ChatSession] {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return [] }
        let data = try Data(contentsOf: fileURL)
        return try PropertyListDecoder().decode([ChatSession].self, from: data)
    }
    
    public func clear() async throws {
        if FileManager.default.fileExists(atPath: fileURL.path) {
            try FileManager.default.removeItem(at: fileURL)
        }
    }
}
