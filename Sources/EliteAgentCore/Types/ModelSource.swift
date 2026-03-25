import Foundation

public enum ModelSource: Sendable, Identifiable, Equatable {
    case openRouter(id: String, name: String, isFree: Bool, contextK: Int, costPer1K: Decimal?)
    case localMLX(id: String, name: String, ramGB: Int, hasThink: Bool)
    
    public var id: String {
        switch self {
        case .openRouter(let id, _, _, _, _): return id
        case .localMLX(let id, _, _, _): return id
        }
    }
    
    public var name: String {
        switch self {
        case .openRouter(_, let name, _, _, _): return name
        case .localMLX(_, let name, _, _): return name
        }
    }
    
    public var icon: String {
        switch self {
        case .openRouter: return "cloud"
        case .localMLX: return "cpu"
        }
    }
    
    public var isFree: Bool {
        switch self {
        case .openRouter(_, _, let free, _, _): return free
        case .localMLX: return true
        }
    }
}
