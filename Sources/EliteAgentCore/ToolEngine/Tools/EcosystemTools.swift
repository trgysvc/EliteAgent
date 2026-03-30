import Foundation

public struct CalendarTool: AgentTool {
    public let name = "apple_calendar"
    public let description = "Schedule and manage events in the native Apple Calendar app using direct system protocols."
    
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
    public let description = "Directly manage Apple Mail drafts and sending."
    
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
