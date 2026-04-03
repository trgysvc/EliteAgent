import Foundation
import Cocoa


public struct MessengerTool: AgentTool {
    public let name = "send_message_via_whatsapp_or_imessage"
    public let description = """
    Send messages via WhatsApp or iMessage.
    For WhatsApp: recipient MUST be a phone number with country code (e.g. +905551234567).
    For iMessage: recipient can be phone number OR Apple ID email.
    If you only have a name, use shell_exec with osascript to look up the number in Contacts first.
    Parameters: platform ('whatsapp' or 'imessage'), recipient (phone/email), message (text).
    """
    
    public init() {}
    
    public func execute(params: [String: AnyCodable], session: Session) async throws -> String {
        guard let platform = params["platform"]?.value as? String,
              let recipient = params["recipient"]?.value as? String,
              let message = params["message"]?.value as? String else {
            throw ToolError.missingParameter("platform, recipient, and message are all required.")
        }
        
        if await AppSettings.shared.isBiometricEnabledForActions {
            print("[SECURITY] Biyometrik doğrulama bekleniyor...")
            let authReason = "\(platform.capitalized) üzerinden mesaj gönderimi için onayınız gerekiyor."
            guard await SecuritySentinel.shared.authenticateUser(reason: authReason) else {
                return "[SECURITY_BLOCK] Biyometrik doğrulama başarısız. Mesaj gönderilemedi."
            }
        }
        
        let looksLikeNumber = recipient.range(of: #"^\+?[\d\s\-\(\)]{7,}$"#, options: .regularExpression) != nil
        let looksLikeEmail = recipient.contains("@")
        
        if !looksLikeNumber && !looksLikeEmail {
            // Resolve name → phone via Contacts.app
            let resolveScript = """
            tell application "Contacts"
                set matchedPeople to (every person whose name contains "\(recipient)")
                if (count of matchedPeople) is 0 then
                    return "NOT_FOUND"
                end if
                set firstPerson to item 1 of matchedPeople
                set phoneList to phones of firstPerson
                if (count of phoneList) is 0 then
                    return "NO_PHONE"
                end if
                return value of item 1 of phoneList
            end tell
            """
            
            do {
                let result = try await AppleScriptRunner.shared.execute(source: resolveScript)
                if result == "NOT_FOUND" {
                    return "[ERROR] '\(recipient)' kişisi Contacts'ta bulunamadı. Telefon numarasını doğrudan gir (ör: +905551234567)."
                }
                if result == "NO_PHONE" {
                    return "[ERROR] '\(recipient)' kişisinin Contacts'ta kayıtlı telefon numarası yok."
                }
                let resolvedPhone = result.trimmingCharacters(in: .whitespacesAndNewlines)
                print("[MESSENGER] '\(recipient)' → \(resolvedPhone) (Contacts'tan çözüldü)")
                
                if platform.lowercased() == "whatsapp" {
                    return try await sendWhatsApp(phone: resolvedPhone, message: message)
                } else {
                    return try await sendIMessage(handle: resolvedPhone, message: message)
                }
            } catch {
                return "[ERROR] Contacts erişimi başarısız: \(error.localizedDescription)"
            }
        }
        
        if platform.lowercased() == "whatsapp" {
            return try await sendWhatsApp(phone: recipient, message: message)
        } else {
            return try await sendIMessage(handle: recipient, message: message)
        }
    }
    
    // MARK: - WhatsApp
    // Düzeltme: Swift """ multiline string AppleScript içine sızıyordu (Error -2741).
    // Çözüm: URL opening için NSWorkspace (AppleScript YOK), keystroke için temp dosya.
    private func sendWhatsApp(phone: String, message: String) async throws -> String {
        let digits = phone.replacingOccurrences(of: "[^0-9]", with: "", options: .regularExpression)

        guard !digits.isEmpty else {
            return "[ERROR] WhatsApp için geçerli bir telefon numarası gerekli. Alıcı: '\(phone)'"
        }

        let encodedMsg = message.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? message
        let urlString = "whatsapp://send?phone=\(digits)&text=\(encodedMsg)"

        // Step 1: Open WhatsApp via NSWorkspace — no AppleScript, no TCC block for URL opening
        guard let url = URL(string: urlString) else {
            return "[ERROR] Geçersiz WhatsApp URL oluşturulamadı."
        }
        NSWorkspace.shared.open(url)
        print("[WHATSAPP] URL açıldı: \(urlString)")

        // Step 2: Wait 3 seconds for WhatsApp to be ready
        try await Task.sleep(nanoseconds: 3_000_000_000)

        // Step 3: Write AppleScript to temp file — avoids Swift """ conflict entirely
        let keystrokeScript = [
            "tell application \"System Events\"",
            "    repeat 15 times",
            "        if exists process \"WhatsApp\" then",
            "            set frontmost of process \"WhatsApp\" to true",
            "            if frontmost of process \"WhatsApp\" then",
            "                delay 1.0",
            "                tell process \"WhatsApp\"",
            "                    keystroke return",
            "                end tell",
            "                return \"SENT\"",
            "            end if",
            "        end if",
            "        delay 0.5",
            "    end repeat",
            "    return \"FAIL: WhatsApp frontmost olamadi\"",
            "end tell"
        ].joined(separator: "\n")

        let tmpPath = "/tmp/eliteagent_wa_\(Int(Date().timeIntervalSince1970)).applescript"
        do {
            try keystrokeScript.write(toFile: tmpPath, atomically: true, encoding: .utf8)
        } catch {
            return "[ERROR] Geçici script dosyası yazılamadı: \(error.localizedDescription)"
        }
        defer { try? FileManager.default.removeItem(atPath: tmpPath) }

        // Step 4: Execute via osascript (Process) — clean, no escaping issues
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = [tmpPath]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe

        do {
            try process.run()
        } catch {
            return "[ERROR] osascript başlatılamadı: \(error.localizedDescription)"
        }

        await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
            DispatchQueue.global(qos: .userInitiated).async {
                process.waitUntilExit()
                cont.resume()
            }
        }

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        let result = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

        print("[WHATSAPP] osascript sonucu: '\(result)'")

        if result == "SENT" {
            return "WhatsApp mesajı +\(digits) numarasına gönderildi."
        }

        var errorMsg = "[ERROR] WhatsApp mesajı gönderilemedi. osascript çıktısı: '\(result)'"
        if result.contains("1002") || result.contains("not allowed") || result.contains("assistive") || result.contains("authorize") {
            errorMsg += "\n[ÇÖZÜM] Sistem Ayarları > Gizlilik ve Güvenlik > Erişilebilirlik > EliteAgent: AÇIK olmalı."
        }
        return errorMsg
    }
    
    // MARK: - iMessage
    private func sendIMessage(handle: String, message: String) async throws -> String {
        let safeMessage = message.replacingOccurrences(of: "\"", with: "\\\"")
        let safeHandle = handle.replacingOccurrences(of: "\"", with: "\\\"")
        
        let script = """
        try
            tell application "Messages"
                set targetService to first service whose service type is iMessage
                set targetBuddy to participant "\(safeHandle)" of targetService
                send "\(safeMessage)" to targetBuddy
            end tell
            return "SENT"
        on error errMsg number errNum
            try
                tell application "Messages"
                    set smsService to first service whose service type is SMS
                    set smsBuddy to participant "\(safeHandle)" of smsService
                    send "\(safeMessage)" to smsBuddy
                end tell
                return "SENT_VIA_SMS"
            on error
                return "FAIL:" & errNum & ":" & errMsg
            end try
        end try
        """
        
        let result = try await AppleScriptRunner.shared.execute(source: script)
        
        if result == "SENT" {
            return "iMessage başarıyla '\(handle)' adresine gönderildi."
        } else if result == "SENT_VIA_SMS" {
            return "Mesaj SMS olarak '\(handle)' numarasına gönderildi."
        } else {
            let parts = result.split(separator: ":", maxSplits: 2)
            let errNum = parts.count > 1 ? String(parts[1]) : "?"
            let errMsg = parts.count > 2 ? String(parts[2]) : result
            var diagnosis = "[ERROR] iMessage gönderilemedi (Hata \(errNum)): \(errMsg)"
            if errNum == "-1728" || errNum == "0" {
                diagnosis += "\n[ÇÖZÜM] Sistem Ayarları > Gizlilik > Otomasyon > EliteAgent > Mesajlar: AÇIK olmalı."
            }
            return diagnosis
        }
    }
}
