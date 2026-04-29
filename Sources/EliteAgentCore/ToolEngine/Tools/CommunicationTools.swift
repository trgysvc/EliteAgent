import Foundation

public struct WhatsAppTool: AgentTool {
    public let name = "whatsapp_send"
    public let summary = "Legacy WhatsApp sender (System Events)."
    public let description = "Send a message via WhatsApp. Parametreler: recipient (phone number or name), message (text)."
    public let ubid: Int128 = 17 // Token '2' in Qwen 2.5
    
    public init() {}
    
    public func execute(params: [String: AnyCodable], session: Session) async throws(AgentToolError) -> String {
        guard let recipient = params["recipient"]?.value as? String,
              let message = params["message"]?.value as? String else {
            throw AgentToolError.missingParameter("recipient and message are required")
        }
        
        let isBiometricEnabled = await AppSettings.shared.isBiometricEnabledForActions
        if isBiometricEnabled {
            let authReason = "WhatsApp üzerinden '\(recipient)' kişisine mesaj göndermek için onayınız gerekiyor."
            guard await SecuritySentinel.shared.authenticateUser(reason: authReason) else {
                return "[SECURITY_BLOCK] Biyometrik doğrulama başarısız. WhatsApp mesajı gönderilemedi."
            }
        }
        
        let script = """
        tell application "WhatsApp"
            activate
            reopen
        end tell
        delay 2.0
        tell application "System Events"
            tell process "WhatsApp"
                -- v10.1: Force Search Focus
                keystroke "f" using command down
                delay 1.0
                -- Clear field
                keystroke "a" using command down
                keystroke (ASCII character 8) -- Backspace
                delay 0.5
                -- Type recipient
                keystroke "\(recipient)"
                delay 2.5
                keystroke return
                delay 1.5
                -- Type message
                keystroke "\(message)"
                delay 0.5
                keystroke return
                return "SUCCESS"
            end tell
        end tell
        """
        
        do {
            let result = try await AppleScriptRunner.shared.execute(source: script)
            if result.contains("SUCCESS") {
                return "WhatsApp mesajı \(recipient) kişisine iletildi komutu gönderildi."
            } else {
                throw AgentToolError.executionError("WhatsApp kontrolü başarısız: \(result)")
            }
        } catch {
            throw AgentToolError.executionError(error.localizedDescription)
        }
    }
}

public struct EmailTool: AgentTool {
    public let name = "send_email"
    public let summary = "Legacy Apple Mail sender."
    public let description = "Send an email via Apple Mail. Parametreler: recipient, subject, body."
    public let ubid: Int128 = 22 // Token '7' in Qwen 2.5
    
    public init() {}
    
    public func execute(params: [String: AnyCodable], session: Session) async throws(AgentToolError) -> String {
        guard let recipient = params["recipient"]?.value as? String,
              let subject = params["subject"]?.value as? String,
              let body = params["body"]?.value as? String else {
            throw AgentToolError.missingParameter("recipient, subject, and body are required")
        }
        
        let isBiometricEnabled = await AppSettings.shared.isBiometricEnabledForActions
        if isBiometricEnabled {
            let authReason = "Mail üzerinden '\(recipient)' adresine e-posta göndermek için onayınız gerekiyor."
            guard await SecuritySentinel.shared.authenticateUser(reason: authReason) else {
                return "[SECURITY_BLOCK] Biyometrik doğrulama başarısız. E-posta gönderilemedi."
            }
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
        
        do {
            _ = try await AppleScriptRunner.shared.execute(source: script)
            return "E-posta \(recipient) adresine gönderildi."
        } catch {
            throw AgentToolError.executionError(error.localizedDescription)
        }
    }
}
