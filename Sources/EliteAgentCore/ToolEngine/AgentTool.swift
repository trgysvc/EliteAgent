import Foundation
import Cocoa

public enum ToolError: LocalizedError, Sendable {
    case missingParameter(String)
    case invalidParameter(String)
    case executionError(String)
    
    public var errorDescription: String? {
        switch self {
        case .missingParameter(let msg): return "Eksik Parametre: \(msg)"
        case .invalidParameter(let msg): return "Geçersiz Parametre: \(msg)"
        case .executionError(let msg): return "Araç Çalıştırma Hatası: \(msg)"
        }
    }
}

public protocol AgentTool: Sendable {
    var name: String { get }
    var description: String { get }
    
    func execute(params: [String: AnyCodable], session: Session) async throws -> String
}
