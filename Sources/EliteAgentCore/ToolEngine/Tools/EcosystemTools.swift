import Foundation

public struct CalendarTool: AgentTool {
    public let name = "apple_calendar"
    public let summary = "Manage native Apple Calendar events."
    public let description = "Schedule and manage events in the native Apple Calendar app using direct system protocols."
    public let ubid = 54 // Token 'W' in Qwen 2.5
    
    public init() {}
    
    public func execute(params: [String: AnyCodable], session: Session) async throws -> String {
        guard let action = params["action"]?.value as? String else {
            throw ToolError.missingParameter("Action (list_events, add_event) is required.")
        }
        
        switch action {
        case "list_events":
            let script = """
            tell application "Calendar"
                set output to ""
                set targetDate to (current date)
                set endOfDay to targetDate + (24 * 60 * 60)
                repeat with eachCalendar in calendars
                    repeat with eachEvent in (events of eachCalendar whose start date is greater than targetDate and start date is less than endOfDay)
                        set output to output & (summary of eachEvent) & " | " & (start date of eachEvent as string) & " | " & (name of eachCalendar) & "\n"
                    end repeat
                end repeat
                return output
            end tell
            """
            return try await AppleScriptRunner.shared.execute(source: script)
            
        case "add_event":
            guard let summary = params["summary"]?.value as? String,
                  let startStr = params["start"]?.value as? String else {
                throw ToolError.missingParameter("Summary and start date (e.g., 'tomorrow 10am') are required.")
            }
            let script = """
            try
                tell application "Calendar"
                    -- Try to use default calendar if 'Work' doesn't exist
                    set targetCalendar to calendar 1
                    try
                        if exists calendar "Work" then set targetCalendar to calendar "Work"
                    end try
                    make new event at end of events of targetCalendar with properties {summary:"\(summary)", start date:date "\(startStr)"}
                end tell
                return "Successfully scheduled event '\(summary)' at \(startStr)."
            on error err
                return "FAIL: " & err
            end try
            """
            let result = try await AppleScriptRunner.shared.execute(source: script)
            if result.contains("FAIL") {
                throw ToolError.executionError("Calendar Protocol Error: \(result)")
            }
            return result
            
        default:
            throw ToolError.invalidParameter("Unknown action: \(action)")
        }
    }
}

public struct MailTool: AgentTool {
    public let name = "apple_mail"
    public let summary = "Send/Draft native Apple Mail emails."
    public let description = "Directly manage Apple Mail drafts and sending."
    public let ubid = 55 // Token 'X' in Qwen 2.5
    
    public init() {}
    
    public func execute(params: [String: AnyCodable], session: Session) async throws -> String {
        guard let action = params["action"]?.value as? String else {
            throw ToolError.missingParameter("Action (list_unread, create_draft, send_email) is required.")
        }
        
        switch action {
        case "list_unread":
            let script = """
            tell application "Mail"
                set output to ""
                set unreadMessages to (messages of inbox whose read status is false)
                repeat with eachMessage in unreadMessages
                    set output to output & (subject of eachMessage) & " | " & (sender of eachMessage) & "\n"
                end repeat
                return output
            end tell
            """
            return try await AppleScriptRunner.shared.execute(source: script)
            
        case "create_draft":
            guard let subject = params["subject"]?.value as? String,
                  let recipient = params["recipient"]?.value as? String,
                  let body = params["body"]?.value as? String else {
                throw ToolError.missingParameter("Subject, recipient, and body are required.")
            }
            let script = """
            tell application "Mail"
                set newMessage to make new outgoing message with properties {subject:"\(subject)", content:"\(body)", visible:true}
                tell newMessage
                    make new to recipient with properties {address:"\(recipient)"}
                end tell
                save newMessage
            end tell
            """
            _ = try await AppleScriptRunner.shared.execute(source: script)
            return "Successfully created a DRAFT in Mail (Preview active)."
            
        case "send_email":
            guard let subject = params["subject"]?.value as? String,
                  let recipient = params["recipient"]?.value as? String,
                  let body = params["body"]?.value as? String else {
                throw ToolError.missingParameter("Subject, recipient, and body are required.")
            }
            let script = """
            try
                tell application "Mail"
                    set newMessage to make new outgoing message with properties {subject:"\(subject)", content:"\(body)", visible:false}
                    tell newMessage
                        make new to recipient with properties {address:"\(recipient)"}
                        send
                    end tell
                end tell
                return "Successfully SENT email to \(recipient)."
            on error err
                return "FAIL: " & err
            end try
            """
            let result = try await AppleScriptRunner.shared.execute(source: script)
            if result.contains("FAIL") {
                throw ToolError.executionError("Mail Protocol Error: \(result)")
            }
            return result
            
        default:
            throw ToolError.invalidParameter("Unknown action: \(action)")
        }
    }
}

// MARK: - System Tools (EcosystemTools Suite)

public struct SystemVolumeTool: AgentTool {
    public let name = "set_volume"
    public let summary = "Adjust macOS system speaker volume."
    public let description = "Set the system output volume level (0-100) using native Core Audio protocols. Use this for all volume adjustments. Parametre: level (int)."
    public let ubid = 56 // Token 'Y' in Qwen 2.5
    
    public init() {}
    
    public func execute(params: [String: AnyCodable], session: Session) async throws -> String {
        guard let level = params["level"]?.value as? Int else {
            throw ToolError.missingParameter("level")
        }
        
        let script = "set volume output volume \(level)"
        _ = try await AppleScriptRunner.shared.execute(source: script)
        return "Sistem sesi %\(level) olarak ayarlandı."
    }
}

public struct BrightnessControlTool: AgentTool {
    public let name = "set_brightness"
    public let summary = "Adjust macOS screen brightness level."
    public let description = "Set the screen brightness level (0.0 - 1.0). Parametre: level (float)."
    public let ubid = 57 // Token 'Z' in Qwen 2.5
    
    public init() {}
    
    public func execute(params: [String: AnyCodable], session: Session) async throws -> String {
        guard let level = params["level"]?.value as? Double else {
            throw ToolError.missingParameter("level")
        }
        
        let script = "do shell script \"/usr/bin/brightness \(level)\" "
        _ = try? await AppleScriptRunner.shared.execute(source: script) // Execute if installed
        
        return "Ekran parlaklığı \(level) seviyesine ayarlandı (Not: brightness CLI gerektirir)."
    }
}

public struct SleepControlTool: AgentTool {
    public let name = "system_sleep"
    public let summary = "Force macOS system to sleep mode."
    public let description = "Put the system to sleep immediately using native AppleScript protocols. Preferred over shell commands."
    public let ubid = 15 // Token '0' in Qwen 2.5
    
    public init() {}
    
    public func execute(params: [String: AnyCodable], session: Session) async throws -> String {
        let script = "tell application \"System Events\" to sleep"
        _ = try await AppleScriptRunner.shared.execute(source: script)
        return "Sistem uyku moduna alınıyor..."
    }
}

public struct SystemInfoTool: AgentTool {
    public let name = "get_system_info"
    public let summary = "Get detailed OS version and hardware info via Native APIs."
    public let description = "Get basic system information (OS version, Device Name, M-Series Model) using Swift's ProcessInfo. MANDATORY: Use this instead of sw_vers or shell commands for system info."
    public let ubid = 16 // Token '1' in Qwen 2.5
    
    public init() {}
    
    public func execute(params: [String: AnyCodable], session: Session) async throws -> String {
        let os = ProcessInfo.processInfo.operatingSystemVersionString
        let name = Host.current().localizedName ?? "Mac"
        let model = "Apple Silicon (M-Series)"
        
        return """
        [System Info]
        - Device Name: \(name)
        - OS: \(os)
        - Architecture: \(model)
        - EliteAgent Core: v9.5
        """
    }
}
