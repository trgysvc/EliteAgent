import Foundation

public enum Capability: String, Codable, Sendable, Hashable {
    case think
    case code
    case general
    case fast
    case long_context
}

public enum ProviderStatus: String, Codable, Sendable {
    case idle
    case ready
    case loading
    case priming
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

public struct UntrustedData: Codable, Sendable {
    public let source: String
    public let content: String
    
    public init(source: String, content: String) {
        self.source = source
        self.content = content
    }
}

// Codable removed: the tools field ([String: any Sendable]) is not Codable-compatible.
// CompletionRequest is never serialised to disk; all callers pass it in-process.
public struct CompletionRequest: Sendable {
    public let taskID: String
    public let systemPrompt: String
    public let messages: [Message]
    public let maxTokens: Int
    public var temperature: Double?
    public var requiredCapabilities: [Capability]?
    public var maxLatencyMs: Int?
    public var sensitivityLevel: SensitivityLevel
    public var complexity: Int
    public var untrustedContext: [UntrustedData]?
    // Native tool calling (mlx-swift-lm ToolSpec = [String: any Sendable])
    public var tools: [[String: any Sendable]]?

    public init(
        taskID: String,
        systemPrompt: String,
        messages: [Message],
        maxTokens: Int,
        temperature: Double? = 0.2,
        requiredCapabilities: [Capability]? = nil,
        maxLatencyMs: Int? = 30_000,
        sensitivityLevel: SensitivityLevel,
        complexity: Int,
        untrustedContext: [UntrustedData]? = nil,
        tools: [[String: any Sendable]]? = nil
    ) {
        self.taskID = taskID
        self.systemPrompt = systemPrompt
        self.messages = messages
        self.maxTokens = maxTokens
        self.temperature = temperature
        self.requiredCapabilities = requiredCapabilities
        self.maxLatencyMs = maxLatencyMs
        self.sensitivityLevel = sensitivityLevel
        self.complexity = complexity
        self.untrustedContext = untrustedContext
        self.tools = tools
    }
}

public struct TokenCount: Codable, Sendable {
    public let prompt: Int
    public let completion: Int
    public let cached: Int // v10.0: Tokens served from KV-cache
    public let total: Int
    
    public init(prompt: Int, completion: Int, cached: Int = 0, total: Int) {
        self.prompt = prompt
        self.completion = completion
        self.cached = cached
        self.total = total
    }
}

public enum ProviderError: Error, Codable, Sendable, CustomStringConvertible {
    case networkError(String)
    case authenticationError
    case rateLimitExceeded
    case emptyResponse
    case timeout
    case unknown(String)
    case modelNotLoaded
    
    public var description: String {
        switch self {
        case .networkError(let err): return "Network error: \(err)"
        case .authenticationError: return "Authentication failed (Check API Key)."
        case .rateLimitExceeded: return "Rate limit exceeded. Please wait."
        case .emptyResponse: return "Empty response from provider (null content)."
        case .timeout: return "Request timed out."
        case .unknown(let msg): return "Unknown error: \(msg)"
        case .modelNotLoaded: return "Model is not loaded."
        }
    }
}

public struct CompletionResponse: Codable, Sendable {
    public let taskID: String
    public let providerUsed: ProviderID
    public let content: String
    public let thinkBlock: String?
    public let toolCalls: [ToolCall]?
    public let tokensUsed: TokenCount
    public let latencyMs: Int
    public let costUSD: Decimal
    public var error: ProviderError?
    
    public init(taskID: String, providerUsed: ProviderID, content: String, thinkBlock: String? = nil, toolCalls: [ToolCall]? = nil, tokensUsed: TokenCount, latencyMs: Int, costUSD: Decimal, error: ProviderError? = nil) {
        self.taskID = taskID
        self.providerUsed = providerUsed
        self.content = content
        self.thinkBlock = thinkBlock
        self.toolCalls = toolCalls
        self.tokensUsed = tokensUsed
        self.latencyMs = latencyMs
        self.costUSD = costUSD
        self.error = error
    }
}

public struct SpeculativeDecodingMetrics: Codable, Sendable {
    public var totalDraftTokensGenerated: Int
    public var acceptedDraftTokens: Int
    
    public init(totalDraftTokensGenerated: Int = 0, acceptedDraftTokens: Int = 0) {
        self.totalDraftTokensGenerated = totalDraftTokensGenerated
        self.acceptedDraftTokens = acceptedDraftTokens
    }
    
    public var acceptanceRate: Double {
        guard totalDraftTokensGenerated > 0 else { return 0.0 }
        return Double(acceptedDraftTokens) / Double(totalDraftTokensGenerated)
    }
}

public enum InferenceChunk: Sendable {
    case token(String)
    case metrics(promptTokens: Int, completionTokens: Int, tps: Double, speculative: SpeculativeDecodingMetrics? = nil)
    case tool(String)
    // Native tool call parsed by mlx-swift-lm (Qwen xmlFunction / OpenAI format)
    case toolCall(name: String, arguments: [String: AnyCodable])
}

extension Notification.Name {
    public static let llmProviderSwitched = Notification.Name("app.eliteagent.llmProviderSwitched")
    public static let llmMemoryPressureAvoided = Notification.Name("app.eliteagent.llmMemoryPressureAvoided")
    public static let activeProviderChanged = Notification.Name("app.eliteagent.activeProviderChanged")
    public static let draftModelLoaded = Notification.Name("app.eliteagent.draftModelLoaded")
}

