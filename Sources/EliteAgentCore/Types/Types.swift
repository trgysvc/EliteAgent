import Foundation
import CryptoKit

public enum AgentID: String, Codable, Sendable {
    case orchestrator
    case planner
    case executor
    case critic
    case memory
    case guard_ = "guard"
    case mcpGateway = "mcp_gateway"
    case browserAgent = "browser_agent"
}

public enum FallbackDecision: String, Codable, Sendable {
    case useCloud
    case useOllama
    case cancel
}

public enum AgentStatus: Sendable, Equatable {
    case idle
    case working
    case waitingLLM
    case waiting
    case healing
    case error
    case awaitingFallbackApproval(taskID: String, error: String)
    
    public var displayString: String {
        switch self {
        case .idle: return "Idle"
        case .working: return "Working"
        case .waitingLLM: return "Waiting for LLM"
        case .waiting: return "Waiting"
        case .healing: return "Healing"
        case .error: return "Error"
        case .awaitingFallbackApproval: return "Awaiting Approval"
        }
    }
}

public struct TaskStep: Identifiable, Codable, Sendable {
    public let id: UUID
    public let name: String
    public let status: String
    public let latency: String
    public let depth: Int
    public let thought: String?
    
    public init(id: UUID = UUID(), name: String, status: String, latency: String, depth: Int = 0, thought: String? = nil) {
        self.id = id
        self.name = name
        self.status = status
        self.latency = latency
        self.depth = depth
        self.thought = thought
    }
}

public struct ToolCall: Codable, Sendable {
    public let tool: String
    public let params: [String: AnyCodable]
    
    public init(tool: String, params: [String: AnyCodable]) {
        self.tool = tool
        self.params = params
    }
}

public struct ThinkBlock: Sendable {
    public let thought: String
    public let toolCall: ToolCall?
    
    public init(thought: String, toolCall: ToolCall? = nil) {
        self.thought = thought
        self.toolCall = toolCall
    }
}

public enum ProviderID: String, Codable, CaseIterable, Sendable {
    case mlx
    case bridge
    case openrouter
    case none
}

public enum ProviderType: String, Codable, Sendable {
    case local
    case cloud
    case bridge
}

public enum FallbackPolicy: String, Codable, Sendable {
    case strictLocal = "strict_local"
    case promptBeforeSwitch = "prompt_before_switch"
    case autoSwitchWithBadge = "auto_switch_with_badge"
}

public struct InferenceConfig: Codable, Sendable {
    public var providerPriority: [ProviderID]
    public var strictLocal: Bool
    public var requireFallbackApproval: Bool
    public var fallbackPolicy: FallbackPolicy
    
    public static let `default` = InferenceConfig(
        providerPriority: [.mlx, .bridge, .openrouter],
        strictLocal: false,
        requireFallbackApproval: true, // Default to true based on user feedback
        fallbackPolicy: .promptBeforeSwitch
    )
}

public struct AgentHealth: Sendable {
    public let isHealthy: Bool
    public let statusMessage: String
    
    public init(isHealthy: Bool, statusMessage: String) {
        self.isHealthy = isHealthy
        self.statusMessage = statusMessage
    }
}

public enum SignalPriority: Int, Sendable {
    case critical = 0
    case high = 1
    case normal = 2
    case low = 3
    
    public var timeoutMs: Int {
        switch self {
        case .critical: return 10_000
        case .high: return 30_000
        case .normal: return 60_000
        case .low: return 120_000
        }
    }
}

public struct Signal: Sendable {
    public let sigID: UUID
    public let source: AgentID
    public let target: AgentID
    public let name: String
    public let priority: SignalPriority
    public let payload: Data
    public let signature: String
    
    public init(sigID: UUID = UUID(), source: AgentID, target: AgentID, name: String, priority: SignalPriority, payload: Data = Data(), secretKey: SymmetricKey) {
        self.sigID = sigID
        self.source = source
        self.target = target
        self.name = name
        self.priority = priority
        self.payload = payload
        
        var dataToSign = Data()
        dataToSign.append(contentsOf: sigID.uuidString.utf8)
        dataToSign.append(contentsOf: source.rawValue.utf8)
        dataToSign.append(contentsOf: target.rawValue.utf8)
        dataToSign.append(contentsOf: name.utf8)
        dataToSign.append(contentsOf: withUnsafeBytes(of: priority.rawValue) { Data($0) })
        dataToSign.append(payload)
        
        let mac = HMAC<SHA256>.authenticationCode(for: dataToSign, using: secretKey)
        self.signature = Data(mac).base64EncodedString()
    }
    
    public func verifySignature(using secretKey: SymmetricKey) -> Bool {
        var dataToSign = Data()
        dataToSign.append(contentsOf: sigID.uuidString.utf8)
        dataToSign.append(contentsOf: source.rawValue.utf8)
        dataToSign.append(contentsOf: target.rawValue.utf8)
        dataToSign.append(contentsOf: name.utf8)
        dataToSign.append(contentsOf: withUnsafeBytes(of: priority.rawValue) { Data($0) })
        dataToSign.append(payload)
        
        let mac = HMAC<SHA256>.authenticationCode(for: dataToSign, using: secretKey)
        let expectedSignature = Data(mac).base64EncodedString()
        return self.signature == expectedSignature
    }
}

public enum SignalError: Error, Sendable {
    case timeout(sigID: UUID, target: AgentID)
    case invalidDirection(source: AgentID, target: AgentID)
}

public struct AnyCodable: Codable {
    public let value: Any
    
    public init(_ value: Any) {
        self.value = value
    }
    
    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let x = try? container.decode(Bool.self) { value = x }
        else if let x = try? container.decode(Int.self) { value = x }
        else if let x = try? container.decode(Double.self) { value = x }
        else if let x = try? container.decode(String.self) { value = x }
        else if let x = try? container.decode([AnyCodable].self) { value = x.map { $0.value } }
        else if let x = try? container.decode([String: AnyCodable].self) { value = x.mapValues { $0.value } }
        else { throw DecodingError.typeMismatch(AnyCodable.self, .init(codingPath: decoder.codingPath, debugDescription: "Wrong type")) }
    }
    
    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        if let x = value as? Bool { try container.encode(x) }
        else if let x = value as? Int { try container.encode(x) }
        else if let x = value as? Double { try container.encode(x) }
        else if let x = value as? String { try container.encode(x) }
        else if let x = value as? [Any] { try container.encode(x.map { AnyCodable($0) }) }
        else if let x = value as? [String: Any] { try container.encode(x.mapValues { AnyCodable($0) }) }
        else { throw EncodingError.invalidValue(value, .init(codingPath: encoder.codingPath, debugDescription: "Unknown type")) }
    }
}

extension AnyCodable: @unchecked Sendable {}

@preconcurrency import Metal
public struct MetalBufferWrapper: @unchecked Sendable {
    public let buffer: (any MTLBuffer)?
    public init(_ buffer: (any MTLBuffer)?) {
        self.buffer = buffer
    }
}
