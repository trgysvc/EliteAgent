import Foundation

public struct MediaControllerTool: AgentTool {
    public let name = "media_control"
    public let description = "Control Apple Music and system sound. Actions: play, pause, next, volume (0-100), play_content (search and play tracks/artists/playlists). Params for play_content: searchTerm (String), contentType (Optional: 'track' or 'playlist'). Use this for any music related requests on macOS."
    
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
            guard var searchTerm = params["searchTerm"]?.value as? String else {
                throw ToolError.missingParameter("SearchTerm is required for play_content action.")
            }
            
            let requestedType = params["contentType"]?.value as? String
            
            // v9.9.5: Clean up common noise but save original for intent check
            let lowerSearch = searchTerm.lowercased()
            let isPlaylistRequested = lowerSearch.contains("playlist") || requestedType == "playlist"
            
            searchTerm = searchTerm.replacingOccurrences(of: "playlist", with: "", options: .caseInsensitive)
                .replacingOccurrences(of: "çalmaya başla", with: "", options: .caseInsensitive)
                .replacingOccurrences(of: "çal", with: "", options: .caseInsensitive)
                .trimmingCharacters(in: .whitespaces)
            
            let script: String
            if isPlaylistRequested {
                script = """
                tell application "Music"
                    try
                        set playlistList to (every playlist whose name contains "\(searchTerm)")
                        if (count of playlistList) > 0 then
                            play (item 1 of playlistList)
                            return "Playing playlist: " & (name of item 1 of playlistList)
                        end if
                        
                        set trackList to (every track whose name contains "\(searchTerm)" or artist contains "\(searchTerm)")
                        if (count of trackList) > 0 then
                            play (item 1 of trackList)
                            return "Playing track: " & (name of item 1 of trackList)
                        end if
                        
                        return "Error: No playlist or track found matching '\(searchTerm)'"
                    on error errText number errNum
                        return "AppleScript Error: " & errText & " (" & (errNum as string) & ")"
                    end try
                end tell
                """
            } else {
                script = """
                tell application "Music"
                    try
                        set trackList to (every track whose name contains "\(searchTerm)" or artist contains "\(searchTerm)")
                        if (count of trackList) > 0 then
                            play (item 1 of trackList)
                            return "Playing track: " & (name of item 1 of trackList)
                        end if
                        
                        set playlistList to (every playlist whose name contains "\(searchTerm)")
                        if (count of playlistList) > 0 then
                            play (item 1 of playlistList)
                            return "Playing playlist: " & (name of item 1 of playlistList)
                        end if
                        
                        return "Error: No track or playlist found matching '\(searchTerm)'"
                    on error errText number errNum
                        return "AppleScript Error: " & errText & " (" & (errNum as string) & ")"
                    end try
                end tell
                """
            }
            return try await AppleScriptRunner.shared.execute(source: script)
        default:
            throw ToolError.invalidParameter("Unknown action: \(action)")
        }
    }
}
