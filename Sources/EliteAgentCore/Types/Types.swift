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

public enum AgentStatus: String, Sendable {
    case idle
    case working
    case waitingLLM = "waiting_llm"
    case waiting
    case error
}

public struct TaskStep: Identifiable, Sendable {
    public let id = UUID()
    public let name: String
    public let status: String
    public let latency: String
    
    public init(name: String, status: String, latency: String) {
        self.name = name
        self.status = status
        self.latency = latency
    }
}

public struct ProviderID: RawRepresentable, Codable, Equatable, Hashable, Sendable {
    public let rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }
}

public enum ProviderType: String, Codable, Sendable {
    case local
    case cloud
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
