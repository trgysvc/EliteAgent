import Foundation

public struct MessengerTool: AgentTool {
    // Improved name and description to ensure usage by Planner/Executor
    public let name = "send_message_via_whatsapp_or_imessage"
    public let description = """
    Send messages via WhatsApp or iMessage. This tool correctly handles Turkish characters 
    (ü, ğ, ş, ı, ö, ç) and UI focus. Use this instead of shell_exec for messaging.
    Parameters: platform ('whatsapp' or 'imessage'), recipient (name or phone), message (text).
    """
    
    public init() {}
    
    public func execute(params: [String: AnyCodable], session: Session) async throws -> String {
        guard let platform = params["platform"]?.value as? String,
              let recipient = params["recipient"]?.value as? String,
              let message = params["message"]?.value as? String else {
            throw ToolError.missingParameter("Platform (whatsapp/imessage), recipient, and message are required.")
        }
        
        // BIOMETRIC SECURITY CHECK (Check settings first)
        if await AppSettings.shared.isBiometricEnabledForActions {
            let authReason = "\(platform.capitalized) üzerinden mesaj gönderimi için onayınız gerekiyor."
            let isAuthenticated = await SecuritySentinel.shared.authenticateUser(reason: authReason)
            
            guard isAuthenticated else {
                return "İptal Edildi: Biyometrik doğrulama başarısız veya kullanıcı tarafından reddedildi."
            }
        }
        
        let normalizedPlatform = platform.lowercased()
        
        if normalizedPlatform == "whatsapp" {
            return try await sendWhatsApp(recipient: recipient, message: message)
        } else if normalizedPlatform == "imessage" || normalizedPlatform == "messages" {
            return try await sendIMessage(recipient: recipient, message: message)
        } else {
            throw ToolError.invalidParameter("Unsupported platform: \(platform). Use 'whatsapp' or 'imessage'.")
        }
    }
    
    private func sendWhatsApp(recipient: String, message: String) async throws -> String {
        let isPhoneNumber = recipient.range(of: "^[+0-9\\s()]+$", options: .regularExpression) != nil
        
        if isPhoneNumber {
            let cleanNumber = recipient.replacingOccurrences(of: "[^0-9]", with: "", options: .regularExpression)
            // Direct URL scheme for numbers is much faster
            let script = """
            open location "whatsapp://send?phone=\(cleanNumber)&text=\(message.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? message)"
            delay 2.0
            tell application "System Events"
                tell process "WhatsApp"
                    set frontmost to true
                    key code 36 -- Enter to send
                end tell
            end tell
            """
            return try await AppleScriptRunner.shared.execute(source: script)
        } else {
            // Updated script based on screenshots: Using CMD+N for New Chat focus
            let script = """
            tell application "WhatsApp" to activate
            delay 1.5
            tell application "System Events"
                tell process "WhatsApp"
                    set frontmost to true
                    -- Using Command+N (New Chat) is more reliable for focusing the search bar
                    keystroke "n" using command down 
                    delay 0.8
                    
                    set the clipboard to "\(recipient)"
                    keystroke "v" using command down -- Paste recipient
                    delay 2.0 -- Wait for results to populate
                    
                    key code 36 -- Enter to select the contact
                    delay 1.0
                end tell
                
                set the clipboard to "\(message)"
                delay 0.3
                tell process "WhatsApp"
                    keystroke "v" using command down -- Paste message
                    delay 0.5
                    key code 36 -- Enter to send
                end tell
            end tell
            """
            return try await AppleScriptRunner.shared.execute(source: script)
        }
    }
    
    private func sendIMessage(recipient: String, message: String) async throws -> String {
        let robustScript = """
        try
            tell application "Messages"
                set targetService to (first service whose service type is iMessage)
                set targetBuddy to buddy "\(recipient)" of targetService
                send "\(message)" to targetBuddy
            end tell
            return "Success"
        on error errMsg
            return "Error: " & errMsg
        end try
        """
        let result = try await AppleScriptRunner.shared.execute(source: robustScript)
        
        if result.contains("Error") {
            // V2 UI automation fallback for iMessage
            let uiScript = """
            tell application "Messages" to activate
            delay 1.5
            tell application "System Events"
                tell process "Messages"
                    keystroke "n" using command down -- New Message
                    delay 0.8
                    set the clipboard to "\(recipient)"
                    keystroke "v" using command down
                    delay 1.0
                    key code 36 -- Enter to select
                    delay 0.5
                end tell
                
                set the clipboard to "\(message)"
                delay 0.3
                tell process "Messages"
                    keystroke "v" using command down
                    delay 0.5
                    key code 36 -- Enter to send
                end tell
            end tell
            """
            return try await AppleScriptRunner.shared.execute(source: uiScript)
        }
        return result
    }
}
