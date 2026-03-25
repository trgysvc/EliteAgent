import Foundation

public enum Capability: String, Codable, Sendable, Hashable {
    case think
    case code
    case general
    case fast
    case long_context
}

public enum ProviderStatus: String, Codable, Sendable {
    case ready
    case loading
    case error
}

public enum SensitivityLevel: String, Codable, Sendable {
    case `public`
    case `internal`
    case confidential
}

public struct Message: Codable, Sendable {
    public let role: String
    public let content: String
    
    public init(role: String, content: String) {
        self.role = role
        self.content = content
    }
}

public struct CompletionRequest: Codable, Sendable {
    public let taskID: String
    public let systemPrompt: String
    public let messages: [Message]
    public let maxTokens: Int
    public var temperature: Double?
    public var requiredCapabilities: [Capability]?
    public var maxLatencyMs: Int?
    public var sensitivityLevel: SensitivityLevel
    public var complexity: Int
    
    public init(taskID: String, systemPrompt: String, messages: [Message], maxTokens: Int, temperature: Double? = 0.2, requiredCapabilities: [Capability]? = nil, maxLatencyMs: Int? = 30_000, sensitivityLevel: SensitivityLevel, complexity: Int) {
        self.taskID = taskID
        self.systemPrompt = systemPrompt
        self.messages = messages
        self.maxTokens = maxTokens
        self.temperature = temperature
        self.requiredCapabilities = requiredCapabilities
        self.maxLatencyMs = maxLatencyMs
        self.sensitivityLevel = sensitivityLevel
        self.complexity = complexity
    }
}

public struct TokenCount: Codable, Sendable {
    public let prompt: Int
    public let completion: Int
    public let total: Int
    
    public init(prompt: Int, completion: Int, total: Int) {
        self.prompt = prompt
        self.completion = completion
        self.total = total
    }
}

public enum ProviderError: Error, Codable, Sendable, CustomStringConvertible {
    case modelNotLoaded
    case timeout
    case networkError(String)
    
    public var description: String {
        switch self {
        case .modelNotLoaded: return "Model is not loaded."
        case .timeout: return "Provider timed out."
        case .networkError(let err): return "Network error: \(err)"
        }
    }
}

public struct CompletionResponse: Codable, Sendable {
    public let taskID: String
    public let providerUsed: ProviderID
    public let content: String
    public let thinkBlock: String?
    public let tokensUsed: TokenCount
    public let latencyMs: Int
    public let costUSD: Decimal
    public var error: ProviderError?
    
    public init(taskID: String, providerUsed: ProviderID, content: String, thinkBlock: String? = nil, tokensUsed: TokenCount, latencyMs: Int, costUSD: Decimal, error: ProviderError? = nil) {
        self.taskID = taskID
        self.providerUsed = providerUsed
        self.content = content
        self.thinkBlock = thinkBlock
        self.tokensUsed = tokensUsed
        self.latencyMs = latencyMs
        self.costUSD = costUSD
        self.error = error
    }
}
