import Foundation

public enum ModelHealthStatus: String, Codable, Sendable {
    case healthy = "Stable"
    case degraded = "Slow"
    case critical = "Recovering"
    case offline = "Offline"
    
    public var icon: String {
        switch self {
        case .healthy: return "checkmark.circle.fill"
        case .degraded: return "exclamationmark.triangle.fill"
        case .critical: return "arrow.clockwise.circle.fill"
        case .offline: return "circlebadge"
        }
    }
    
    public var colorName: String {
        switch self {
        case .healthy: return "green"
        case .degraded: return "orange"
        case .critical: return "red"
        case .offline: return "gray"
        }
    }
}

public struct InferenceMetrics: Codable, Sendable {
    public let tokensPerSec: Double
    let latencyMs: Int
    public let vramUsage: Double // 0.0 - 1.0
    public let thermalState: Int // ProcessInfo.ThermalState.rawValue
    public let errorRate: Double // 0.0 - 1.0
    
    public static let zero = InferenceMetrics(
        tokensPerSec: 0,
        latencyMs: 0,
        vramUsage: 0,
        thermalState: 0,
        errorRate: 0
    )
    
    public var diagnostic: String {
        let thermalStr: String
        switch thermalState {
        case 0: thermalStr = "Nominal"
        case 1: thermalStr = "Fair"
        case 2: thermalStr = "Serious"
        case 3: thermalStr = "Critical"
        default: thermalStr = "Unknown"
        }
        return "\(Int(tokensPerSec)) tok/s • VRAM: \(Int(vramUsage * 100))% • Thermal: \(thermalStr)"
    }
}

public struct MetricSample: Identifiable, Codable, Sendable {
    public let id: UUID
    public let timestamp: Date
    public let tokensPerSec: Float
    public let latencyMs: Float
    public let vramUsage: Float // 0.0 - 1.0
    public let thermalState: Int // 0=Nominal, 1=Fair, 2=Serious, 3=Critical
    public let status: ModelHealthStatus
    
    public init(id: UUID = UUID(), timestamp: Date = Date(), tokensPerSec: Float, latencyMs: Float, vramUsage: Float, thermalState: Int, status: ModelHealthStatus) {
        self.id = id
        self.timestamp = timestamp
        self.tokensPerSec = tokensPerSec
        self.latencyMs = latencyMs
        self.vramUsage = vramUsage
        self.thermalState = thermalState
        self.status = status
    }
}
