import Foundation

public struct WhatsAppTool: AgentTool {
    public let name = "whatsapp_send"
    public let description = "Send a message via WhatsApp. Parametreler: recipient (phone number or name), message (text)."
    
    public init() {}
    
    public func execute(params: [String: AnyCodable], session: Session) async throws -> String {
        guard let recipient = params["recipient"]?.value as? String,
              let message = params["message"]?.value as? String else {
            throw ToolError.missingParameter("recipient and message are required")
        }
        
        let script = """
        tell application "WhatsApp"
            activate
            reopen
        end tell
        delay 1.5
        tell application "System Events"
            if (count (processes whose name is "WhatsApp")) > 0 then
                keystroke "n" using command down
                delay 1.0
                keystroke "\(recipient)"
                delay 2.0
                keystroke return
                delay 1.0
                keystroke "\(message)"
                delay 0.5
                keystroke return
                return "SUCCESS"
            else
                return "ERROR: WhatsApp process not found"
            end if
        end tell
        """
        
        let result = try await AppleScriptRunner.shared.execute(source: script)
        if result.contains("SUCCESS") {
            return "WhatsApp mesajı \(recipient) kişisine iletildi komutu gönderildi."
        } else {
            throw ToolError.executionError("WhatsApp kontrolü başarısız: \(result)")
        }
    }
}

public struct EmailTool: AgentTool {
    public let name = "send_email"
    public let description = "Send an email via Apple Mail. Parametreler: recipient, subject, body."
    
    public init() {}
    
    public func execute(params: [String: AnyCodable], session: Session) async throws -> String {
        guard let recipient = params["recipient"]?.value as? String,
              let subject = params["subject"]?.value as? String,
              let body = params["body"]?.value as? String else {
            throw ToolError.missingParameter("recipient, subject, and body are required")
        }
        
        let script = """
        tell application "Mail"
            set newMessage to make new outgoing message with properties {subject:"\(subject)", content:"\(body)", visible:true}
            tell newMessage
                make new to recipient with properties {address:"\(recipient)"}
                send
            end tell
        end tell
        """
        
        _ = try await AppleScriptRunner.shared.execute(source: script)
        return "E-posta \(recipient) adresine gönderildi."
    }
}
