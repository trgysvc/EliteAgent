import Foundation
import Cocoa

public enum AgentToolError: LocalizedError, Sendable {
    case missingParameter(String)
    case invalidParameter(String)
    case executionError(String)
    case toolNotFound(String)
    
    public var errorDescription: String? {
        switch self {
        case .missingParameter(let msg): return "Eksik Parametre: \(msg)"
        case .invalidParameter(let msg): return "Geçersiz Parametre: \(msg)"
        case .executionError(let msg): return "Araç Çalıştırma Hatası: \(msg)"
        case .toolNotFound(let identifier): return "Araç Bulunamadı: \(identifier)"
        }
    }
}

public protocol AgentTool: Sendable {
    var name: String { get }
    var summary: String { get }        // v13.8: Lightweight discovery summary
    var description: String { get }
    var ubid: Int128 { get }           // v20.0: High-Precision Binary ID (Swift 6.3)
    
    func execute(params: [String: AnyCodable], session: Session) async throws(AgentToolError) -> String
}
