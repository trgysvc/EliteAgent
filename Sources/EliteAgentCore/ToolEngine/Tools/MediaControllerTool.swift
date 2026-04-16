import Foundation

public struct MediaControllerTool: AgentTool {
    public let name = "media_control"
    public let summary = "Control Apple Music / System Audio."
    public let description = "Control Apple Music and system sound. CRITICAL: The toolID MUST be 'media_control'. Pass action via 'params'. Actions: 'play', 'pause', 'next', 'volume' (requires 'level' 0-100), 'play_content' (requires 'searchTerm' String, optional 'contentType' as 'track' or 'playlist'). Example: {\"toolID\": \"media_control\", \"params\": {\"action\": \"play_content\", \"searchTerm\": \"Coffee playlist\"}}"
    public let ubid = 43 // Token 'L' in Qwen 2.5
    
    public init() {}
    
    public func execute(params: [String: AnyCodable], session: Session) async throws -> String {
        guard let action = params["action"]?.value as? String else {
            throw AgentToolError.missingParameter("Action parameter is required (play, pause, next, volume, play_content).")
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
                let fallbackLevel = params["level"]?.value as? Double
                let finalLevel = Int(fallbackLevel ?? 50)
                return try await AppleScriptRunner.shared.execute(source: "set volume output volume \(finalLevel)")
            }
            return try await AppleScriptRunner.shared.execute(source: "set volume output volume \(level)")
        case "play_content":
            guard var searchTerm = params["searchTerm"]?.value as? String else {
                throw AgentToolError.missingParameter("SearchTerm is required for play_content action.")
            }
            
            let requestedType = params["contentType"]?.value as? String
            let lowerSearch = searchTerm.lowercased()
            let isPlaylistRequested = lowerSearch.contains("playlist") || requestedType == "playlist"
            
            searchTerm = searchTerm.replacingOccurrences(of: "playlist", with: "", options: .caseInsensitive)
                .replacingOccurrences(of: "çalmaya başla", with: "", options: .caseInsensitive)
                .replacingOccurrences(of: "çal", with: "", options: .caseInsensitive)
                .trimmingCharacters(in: .whitespaces)
            
            // v11.4: Using STABLE templates to prevent Error -2741 (Syntax error)
            let script: String
            if isPlaylistRequested {
                script = """
                tell application "Music"
                    activate
                    try
                        set foundPlaylist to (every playlist whose name contains "\(searchTerm)")
                        if (count of foundPlaylist) > 0 then
                            play (item 1 of foundPlaylist)
                            return "Playing playlist: " & (name of item 1 of foundPlaylist)
                        else
                            return "NOT_FOUND: Apple Music arşivinde '\(searchTerm)' isimli bir playlist bulunamadı."
                        end if
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
                        set trackList to (every track whose name contains "\(searchTerm)")
                        if (count of trackList) is 0 then
                             set trackList to (every track whose artist contains "\(searchTerm)")
                        end if
                        
                        if (count of trackList) > 0 then
                            play (item 1 of trackList)
                            return "Playing track: " & (name of item 1 of trackList)
                        else
                            set searchResult to (search library 1 for "\(searchTerm)")
                            if (count of searchResult) > 0 then
                                play (item 1 of searchResult)
                                return "Playing search result: " & (name of item 1 of searchResult)
                            else
                                return "NOT_FOUND: Apple Music arşivinde '\(searchTerm)' parçası bulunamadı. Farklı bir şarkı arayayım mı?"
                            end if
                        end if
                    on error errText
                        return "Error: " & errText
                    end try
                end tell
                """
            }
            return try await AppleScriptRunner.shared.execute(source: script)
        default:
            throw AgentToolError.invalidParameter("Unknown action: \(action)")
        }
    }
}
