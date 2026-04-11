import Foundation

public struct HealingStrategy: Sendable {
    public let name: String
    public let command: String?
    public let description: String
}

public actor SelfHealingEngine {
    public static let shared = SelfHealingEngine()
    
    private var retryCounts: [String: Int] = [:]
    private let maxRetries = 5
    
    private init() {}
    
    public func analyze(error: String, tool: String) -> HealingStrategy? {
        let err = error.lowercased()
        
        // macOS TCC / Automation permission block (AppleScript Error 0 or -1743)
        if err.contains("applescript error 0") || err.contains("error 0:") || err.contains("-1743") {
            return HealingStrategy(
                name: "TCC_PERMISSION",
                command: nil,
                description: """
                [İZİN HATASI] macOS, EliteAgent'ın bu uygulamayı kontrol etmesini engelledi.
                Çözüm: Sistem Ayarları > Gizlilik ve Güvenlik > Otomasyon > EliteAgent satırını bul ve ilgili uygulamaya (Mesajlar, WhatsApp, Takvim) izin ver.
                """
            )
        }
        
        // AppleScript Error -43: File/Application not found (FSFindFolder failure in WhatsApp)
        if err.contains("-43") || err.contains("fsfind") || err.contains("error=-43") {
            return HealingStrategy(
                name: "APP_NOT_FOUND",
                command: nil,
                description: """
                [UYGULAMA HATASI] Hedef uygulama bulunamadı veya eski bir API çağrısı başarısız oldu (FSFindFolder -43).
                WhatsApp için bu genellikle URL Scheme yöntemiyle aşılır. Uygulama kurulu mu kontrol edin.
                """
            )
        }
        
        // XPC connection failure
        if err.contains("os/kern") || err.contains("0x5") || err.contains("xpc") {
            return HealingStrategy(
                name: "XPC_FAILURE",
                command: nil,
                description: """
                [XPC HATASI] Servis bağlantısı kurulamadı. EliteAgent'ın sandboxsuz çalıştığından emin olun.
                Bu hata ShellTool XPC servisinden kaynaklanıyordu — artık doğrudan Process() kullanılıyor.
                """
            )
        }
        
        // iMessage: buddy not found by name (-1728)
        if err.contains("-1728") || err.contains("buddy") {
            return HealingStrategy(
                name: "IMESSAGE_HANDLE",
                command: nil,
                description: """
                [iMESSAGE HATASI] İsimle kişi bulunamadı. iMessage için 'buddy' değil 'participant' kullanılmalı.
                Alıcıyı isim olarak değil telefon numarası (+905XXXXXXXXX) veya Apple ID e-postası olarak gir.
                """
            )
        }
        
        // Command not found
        if err.contains("command not found") {
            let pkg = extractPackage(from: err) ?? "deno"
            return HealingStrategy(name: "INSTALL_PKG", command: "brew install \(pkg)", description: "Missing tool '\(pkg)' detected. Attempting homebrew installation.")
        }
        
        if err.contains("permission denied") {
            return HealingStrategy(name: "SUDO_ESC", command: nil, description: "Access restricted. Check file permissions or run with appropriate privileges.")
        }
        
        if err.contains("port in use") || err.contains("address already in use") {
            return HealingStrategy(name: "FREE_PORT", command: "killall -9 node", description: "Port conflict detected. Attempting to clear existing processes.")
        }
        
        return nil
    }
    
    public func canRetry(error: String) -> Bool {
        let count = retryCounts[error] ?? 0
        return count < maxRetries
    }
    
    public func recordRetry(error: String) {
        retryCounts[error, default: 0] += 1
    }
    
    private func extractPackage(from error: String) -> String? {
        // Simple regex or string splitting to find the command name
        // e.g., "sh: line 1: htop: command not found"
        let parts = error.split(separator: ":")
        if parts.count > 2 {
            return parts[2].trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return nil
    }
}
