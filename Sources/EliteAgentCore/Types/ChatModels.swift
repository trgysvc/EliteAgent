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
    
    public init(id: UUID = UUID(), role: ChatRole, content: String, timestamp: Date = Date()) {
        self.id = id
        self.role = role
        self.content = content
        self.timestamp = timestamp
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
        let home = FileManager.default.homeDirectoryForCurrentUser
        self.fileURL = home.appendingPathComponent(".eliteagent/history.json")
        try? FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
    }
    
    public func save(_ sessions: [ChatSession]) async throws {
        let data = try JSONEncoder().encode(sessions)
        try data.write(to: fileURL, options: .atomic)
    }
    
    public func load() async throws -> [ChatSession] {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return [] }
        let data = try Data(contentsOf: fileURL)
        return try JSONDecoder().decode([ChatSession].self, from: data)
    }
    
    public func clear() async throws {
        if FileManager.default.fileExists(atPath: fileURL.path) {
            try FileManager.default.removeItem(at: fileURL)
        }
    }
}
