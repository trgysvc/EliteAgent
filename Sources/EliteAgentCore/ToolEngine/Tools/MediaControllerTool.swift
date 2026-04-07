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
                    activate
                    try
                        set playlistList to (every playlist whose name contains "\(searchTerm)")
                        if (count of playlistList) > 0 then
                            play (item 1 of playlistList)
                            return "Playing playlist: " & (name of item 1 of playlistList)
                        end if
                        
                        -- Fallback: Search globally and play top playlist result
                        return "No local playlist found for '\(searchTerm)'"
                    on error errText
                        return "Error: " & errText
                    end try
                end tell
                """
            } else {
                script = """
                tell application "Music"
                    activate
                    try
                        -- v10.1: Multi-stage Search (Track + Artist)
                        set trackList to (every track whose name contains "\(searchTerm)")
                        if (count of trackList) is 0 then
                             set trackList to (every track whose artist contains "\(searchTerm)")
                        end if
                        
                        if (count of trackList) > 0 then
                            play (item 1 of trackList)
                            return "Playing local track: " & (name of item 1 of trackList)
                        else
                            -- v10.1: Final Fallback - Use Native Search UI logic (if possible) 
                            -- For simplicity, we just notify of failure or use "play track 1 of (search library area for...)"
                            -- but AppleScript search library is better:
                            set searchResult to (search library 1 for "\(searchTerm)")
                            if (count of searchResult) > 0 then
                                play (item 1 of searchResult)
                                return "Found and playing search result: " & (name of item 1 of searchResult)
                            end if
                        end if
                        
                        return "Error: No track or playlist found matching '\(searchTerm)'"
                    on error errText
                        return "Error: " & errText
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
