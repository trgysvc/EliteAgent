import Foundation
import Cocoa

public enum ToolError: Error, Sendable {
    case missingParameter(String)
    case invalidParameter(String)
    case executionError(String)
}

public protocol AgentTool: Sendable {
    var name: String { get }
    var description: String { get }
    
    func execute(params: [String: AnyCodable], session: Session) async throws -> String
}
