import Foundation

public enum ModelSource: Sendable, Identifiable, Equatable {
    case openRouter(id: String, name: String, isFree: Bool, contextK: Int, promptPrice: Decimal?, completionPrice: Decimal?)
    case localMLX(id: String, name: String, ramGB: Int, hasThink: Bool)
    case custom(providerID: String, name: String, modelID: String, type: ProviderType, isReasoning: Bool)
    
    public var id: String {
        switch self {
        case .openRouter(let id, _, _, _, _, _): return id
        case .localMLX(let id, _, _, _): return id
        case .custom(let providerID, _, _, _, _): return providerID
        }
    }
    
    public var name: String {
        switch self {
        case .openRouter(_, let name, _, _, _, _): return name
        case .localMLX(_, let name, _, _): return name
        case .custom(_, let name, _, _, _): return name
        }
    }
    
    public var icon: String {
        switch self {
        case .openRouter: return "cloud"
        case .localMLX: return "cpu"
        case .custom(_, _, _, let type, _): return type == .local ? "cpu.badge.plus" : "cloud.badge.plus"
        }
    }
    
    public var isFree: Bool {
        switch self {
        case .openRouter(_, _, let free, _, _, _): return free
        case .localMLX: return true
        case .custom: return false // Assume custom might have cost, but usually local is free
        }
    }
    
    public var totalPrice: Decimal {
        switch self {
        case .openRouter(_, _, _, _, let p, let c): return (p ?? 0) + (c ?? 0)
        case .localMLX: return 0
        case .custom: return 0
        }
    }
}
