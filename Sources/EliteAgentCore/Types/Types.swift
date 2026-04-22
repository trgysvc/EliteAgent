import CryptoKit

public protocol UNOAction: Codable, Sendable {
    var toolID: String { get }
    var params: [String: AnyCodable] { get }
}

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

public enum EliteOutputType: String, Codable, Sendable {
    case tool_call
    case response
    case unknown
}

public enum TaskCategory: String, Codable, Sendable, CaseIterable {
    case research
    case fileProcessing
    case audioAnalysis
    case systemManagement
    case codeGeneration
    case dataProcessing
    case multiStepWorkflow
    case applicationAutomation
    case computerUseAX
    case conversation
    case hardware
    case status
    case weather
    case vision
    case chat
    case task
    case other
}

public enum InferenceState: String, Codable, Sendable {
    case idle
    case classifying
    case chatting
    case planning
    case executing
    case reporting
    case reviewing
    case completed
}

public struct EliteAgentOutput: Codable, Sendable {
    public var type: EliteOutputType?    // v10.5.7: Optional to handle LLMs that skip the type field
    public var thought: String?          // Akıl yürütme süreci (reasoning)
    public var content: String?          // type == .response ise
    public var action: String?           // type == .tool_call ise
    public var ubid: Int128?               // v20.0: High-Precision Binary ID (Swift 6.3)
    public var params: [String: AnyCodable]? // type == .tool_call ise
    public var steps: [ToolCall]?        // v10.5.6: Çok adımlı plan desteği
    
    public init(type: EliteOutputType?, thought: String? = nil, content: String? = nil, action: String? = nil, ubid: Int128? = nil, params: [String: AnyCodable]? = nil, steps: [ToolCall]? = nil) {
        self.type = type
        self.thought = thought
        self.content = content
        self.action = action
        self.ubid = ubid
        self.params = params
        self.steps = steps
    }
    
    // v10.5.8: Ultra-resilient decoding for LLM variations
    private struct DynamicCodingKeys: CodingKey {
        var stringValue: String
        init?(stringValue: String) { self.stringValue = stringValue }
        var intValue: Int? { return nil }
        init?(intValue: Int) { return nil }
    }
    
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: DynamicCodingKeys.self)
        
        // Decode fields with alias support
        self.thought = try? container.decodeIfPresent(String.self, forKey: DynamicCodingKeys(stringValue: "thought")!)
        
        // v10.5.8: Match 'content', 'result', 'message', 'text', 'final_answer', or 'observation'
        if let c = try? container.decodeIfPresent(String.self, forKey: DynamicCodingKeys(stringValue: "content")!) { self.content = c }
        else if let c = try? container.decodeIfPresent(String.self, forKey: DynamicCodingKeys(stringValue: "result")!) { self.content = c }
        else if let c = try? container.decodeIfPresent(String.self, forKey: DynamicCodingKeys(stringValue: "message")!) { self.content = c }
        else if let c = try? container.decodeIfPresent(String.self, forKey: DynamicCodingKeys(stringValue: "text")!) { self.content = c }
        else if let c = try? container.decodeIfPresent(String.self, forKey: DynamicCodingKeys(stringValue: "final_answer")!) { self.content = c }
        else if let c = try? container.decodeIfPresent(String.self, forKey: DynamicCodingKeys(stringValue: "observation")!) { self.content = c }
        else if let c = try? container.decodeIfPresent(String.self, forKey: DynamicCodingKeys(stringValue: "weather")!) { self.content = c }
        else {
            // v10.5.9: Ultra-catch-all. If no standard key is found, look for any String field.
            for key in container.allKeys {
                if let val = try? container.decode(String.self, forKey: key), !val.isEmpty, key.stringValue != "thought", key.stringValue != "type" {
                    self.content = val
                    break
                }
            }
        }
        
        self.action = try? container.decodeIfPresent(String.self, forKey: DynamicCodingKeys(stringValue: "action")!)
        self.params = try? container.decodeIfPresent([String: AnyCodable].self, forKey: DynamicCodingKeys(stringValue: "params")!)
        self.steps = try? container.decodeIfPresent([ToolCall].self, forKey: DynamicCodingKeys(stringValue: "steps")!)
        
        // Infer type if missing
        if let typeStr = try? container.decodeIfPresent(String.self, forKey: DynamicCodingKeys(stringValue: "type")!),
           let explicitType = EliteOutputType(rawValue: typeStr) {
            self.type = explicitType
        } else {
            if steps != nil || action != nil {
                self.type = .tool_call
            } else if content != nil {
                self.type = .response
            } else {
                self.type = .unknown
            }
        }
    }
}

public struct ToolCall: Codable, Sendable {
    public var tool: String
    public var ubid: Int128?               // v20.0: High-Precision Binary ID (Swift 6.3)
    public var params: [String: AnyCodable]
    
    public init(tool: String, ubid: Int128? = nil, params: [String: AnyCodable]) {
        self.tool = tool
        self.ubid = ubid
        self.params = params
    }
    
    // v10.5.8: Ultra-resilient decoding for local model variations
    private struct DynamicCodingKeys: CodingKey {
        var stringValue: String
        init?(stringValue: String) { self.stringValue = stringValue }
        var intValue: Int? { return nil }
        init?(intValue: Int) { return nil }
    }
    
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: DynamicCodingKeys.self)
        
        // Match permutations of tool name
        if let t = try? container.decodeIfPresent(String.self, forKey: DynamicCodingKeys(stringValue: "tool")!) { self.tool = t }
        else if let t = try? container.decodeIfPresent(String.self, forKey: DynamicCodingKeys(stringValue: "toolID")!) { self.tool = t }
        else if let t = try? container.decodeIfPresent(String.self, forKey: DynamicCodingKeys(stringValue: "action")!) { self.tool = t }
        else if let t = try? container.decodeIfPresent(String.self, forKey: DynamicCodingKeys(stringValue: "name")!) { self.tool = t }
        else {
            self.tool = "unknown_tool"
        }
        
        // Match permutations of parameters
        if let p = try? container.decodeIfPresent([String: AnyCodable].self, forKey: DynamicCodingKeys(stringValue: "params")!) { self.params = p }
        else if let p = try? container.decodeIfPresent([String: AnyCodable].self, forKey: DynamicCodingKeys(stringValue: "parameters")!) { self.params = p }
        else if let p = try? container.decodeIfPresent([String: AnyCodable].self, forKey: DynamicCodingKeys(stringValue: "arguments")!) { self.params = p }
        else {
            self.params = [:]
        }
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

public struct UNOResponse: Codable, Sendable {
    public let result: String
    public let error: String?
    public let version: Int
    
    public init(result: String, error: String? = nil, version: Int = 1) {
        self.result = result
        self.error = error
        self.version = version
    }
}

public protocol UNOToolExecutor {
    func execute(action: UNOActionWrapper) async throws -> UNOResponse
}

// Wrapper for passing any UNOAction over the wire
public struct UNOActionWrapper: Codable, Sendable {
    public let toolID: String
    public let params: [String: AnyCodable]
    public let version: Int
    
    public init(toolID: String, params: [String: AnyCodable], version: Int = 1) {
        self.toolID = toolID
        self.params = params
        self.version = version
    }
}

public enum ProviderID: String, Codable, CaseIterable, Sendable {
    case mlx
    case openrouter
    case none
}

public enum ProviderType: String, Codable, Sendable {
    case local
    case cloud
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
    public var fallbackPolicy: FallbackPolicy = .promptBeforeSwitch
    public var enabledTools: [String: Bool] = [:]
    
    // Research Mode Settings
    public var isSafariAutomationEnabled: Bool = true
    public var isDeepResearchEnabled: Bool = false
    public var showResearchProgress: Bool = true
    public var autoSaveReports: Bool = false
    public var preferredSearchProvider: String = "Serper (Google)"
    public var maxTokens: Int = 1024
    public var systemPrompt: String? = nil
    
    // v10.0: Titan Hub (Local API Server)
    public var isLocalServerEnabled: Bool = false
    public var localServerPort: Int = 11500
    
    public init(
        providerPriority: [ProviderID] = [.mlx, .openrouter],
        strictLocal: Bool = false,
        requireFallbackApproval: Bool = true,
        fallbackPolicy: FallbackPolicy = .promptBeforeSwitch,
        enabledTools: [String: Bool] = [:],
        isSafariAutomationEnabled: Bool = true,
        isDeepResearchEnabled: Bool = false,
        showResearchProgress: Bool = true,
        autoSaveReports: Bool = false,
        preferredSearchProvider: String = "Serper (Google)",
        maxTokens: Int = 1024,
        systemPrompt: String? = nil,
        isLocalServerEnabled: Bool = false,
        localServerPort: Int = 11500
    ) {
        self.providerPriority = providerPriority
        self.strictLocal = strictLocal
        self.requireFallbackApproval = requireFallbackApproval
        self.fallbackPolicy = fallbackPolicy
        self.enabledTools = enabledTools
        self.isSafariAutomationEnabled = isSafariAutomationEnabled
        self.isDeepResearchEnabled = isDeepResearchEnabled
        self.showResearchProgress = showResearchProgress
        self.autoSaveReports = autoSaveReports
        self.preferredSearchProvider = preferredSearchProvider
        self.maxTokens = maxTokens
        self.systemPrompt = systemPrompt
        self.isLocalServerEnabled = isLocalServerEnabled
        self.localServerPort = localServerPort
    }
    
    public static let `default` = InferenceConfig(
        providerPriority: [.mlx, .openrouter],
        strictLocal: false,
        requireFallbackApproval: true,
        fallbackPolicy: .promptBeforeSwitch,
        enabledTools: [
            "shell_exec": true, "read_file": true, "write_file": true,
            "app_discovery": true, "system_telemetry": true, "patch_tool": true,
            "git_tool": true, "messenger": true, "calendar": true, "mail": true,
            "safari_automation": true, "music_dna": true
        ],
        isSafariAutomationEnabled: true,
        isDeepResearchEnabled: false,
        showResearchProgress: true,
        autoSaveReports: false,
        preferredSearchProvider: "Serper (Google)",
        maxTokens: 1024,
        systemPrompt: "You are EliteAgent, a high-performance AI assistant.",
        isLocalServerEnabled: false,
        localServerPort: 11500
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
