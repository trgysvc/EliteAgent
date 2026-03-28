import Foundation

public enum SessionStatus: String, Codable, Sendable {
    case idle
    case thinking
    case executing
    case verifying
    case finished
    case failed
    case healing
}

public actor Session: Identifiable {
    public let id: UUID
    public let parentID: UUID?
    public let recursionDepth: Int
    public let maxRecursionDepth: Int
    public let workspaceURL: URL
    
    public private(set) var status: SessionStatus = .idle
    public private(set) var tokenUsage: Int = 0
    public private(set) var healingAttempts: Int = 0
    public private(set) var finalAnswer: String?
    
    public init(id: UUID = UUID(), 
                parentID: UUID? = nil, 
                recursionDepth: Int = 0, 
                maxRecursionDepth: Int = 5,
                workspaceURL: URL) {
        self.id = id
        self.parentID = parentID
        self.recursionDepth = recursionDepth
        self.maxRecursionDepth = maxRecursionDepth
        self.workspaceURL = workspaceURL
    }
    
    public func updateStatus(_ newStatus: SessionStatus, finalAnswer: String? = nil) {
        self.status = newStatus
        if let answer = finalAnswer {
            self.finalAnswer = answer
        }
    }
    
    public func addTokenUsage(_ count: Int) {
        self.tokenUsage += count
    }
    
    public func recordHealingAttempt() {
        self.healingAttempts += 1
    }
    
    public func isRecursionLimitReached() -> Bool {
        return recursionDepth >= maxRecursionDepth
    }
}
