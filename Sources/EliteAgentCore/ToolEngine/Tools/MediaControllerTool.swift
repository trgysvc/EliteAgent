import Foundation

public struct MediaControllerTool: AgentTool {
    public let name = "media_control"
    public let description = "Control Apple Music and system volume."
    
    public init() {}
    
    public func execute(params: [String: AnyCodable], session: Session) async throws -> String {
        guard let action = params["action"]?.value as? String else {
            throw ToolError.missingParameter("Action parameter is required (play, pause, next, volume, play_content).")
        }
        
        switch action {
        case "play":
            return try await AppleScriptRunner.shared.execute(source: "tell application \"Music\" to play")
        case "pause":
            return try await AppleScriptRunner.shared.execute(source: "tell application \"Music\" to pause")
        case "next":
            return try await AppleScriptRunner.shared.execute(source: "tell application \"Music\" to next track")
        case "volume":
            guard let level = params["level"]?.value as? Int else {
                throw ToolError.missingParameter("Level (0-100) is required for volume action.")
            }
            return try await AppleScriptRunner.shared.execute(source: "set volume output volume \(level)")
        case "play_content":
            guard let searchTerm = params["searchTerm"]?.value as? String else {
                throw ToolError.missingParameter("SearchTerm is required for play_content action.")
            }
            let script = """
            tell application "Music"
                play (first track whose name contains "\(searchTerm)" or artist contains "\(searchTerm)")
            end tell
            """
            return try await AppleScriptRunner.shared.execute(source: script)
        default:
            throw ToolError.invalidParameter("Unknown action: \(action)")
        }
    }
}
