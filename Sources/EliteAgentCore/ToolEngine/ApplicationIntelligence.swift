import Foundation

/// ApplicationIntelligence: EliteAgent'ın macOS uygulamaları hakkındaki evrensel bilgisini saklayan merkez.
/// Bu "Merkezi Bilgi Havuzu", ajanın hangi uygulamanın nasıl yönetileceğini (AppleScript, UI hiyerarşisi vb.) 
/// bilmesini sağlar.
public struct ApplicationIntelligence: Sendable {
    public static let shared = ApplicationIntelligence()
    
    /// Uygulama bazlı otomasyon stratejileri
    public enum AutomationStrategy: String, Sendable {
        case appleScript = "AppleScript/JXA"
        case urlScheme = "URL Scheme"
        case accessibilityUI = "Accessibility (AXUIElement)"
        case terminalCLI = "Terminal / CLI"
    }
    
    public struct AppProfile: Sendable {
        public let bundleID: String
        public let name: String
        public let strategy: AutomationStrategy
        public let instructions: String
        public let commonScripts: [String: String]
    }
    
    private let registry: [String: AppProfile]
    
    private init() {
        // Ön tanımlı kritik uygulama bilgileri (Knowledge Base)
        self.registry = [
            "net.whatsapp.WhatsApp": AppProfile(
                bundleID: "net.whatsapp.WhatsApp",
                name: "WhatsApp",
                strategy: .urlScheme,
                instructions: "REQUIRES phone number in E.164 format (e.g. +905551234567). Use URL scheme: open location 'whatsapp://send?phone=NUMBER&text=MESSAGE'. WhatsApp has NO AppleScript dictionary. If recipient is a name, resolve via Contacts.app first. After URL opens, bring WhatsApp to front and press Enter (key code 36) to send.",
                commonScripts: [
                    "sendByPhone": "open location 'whatsapp://send?phone=PHONE&text=MESSAGE'"
                ]
            ),
            "com.apple.MobileSMS": AppProfile(
                bundleID: "com.apple.MobileSMS",
                name: "iMessage",
                strategy: .appleScript,
                instructions: "Use 'participant HANDLE of targetService' — NOT 'buddy NAME'. Handle must be phone number (+905551234567) or Apple ID email. Requires Automation permission for Messages.app in System Settings > Privacy > Automation. SMS fallback available via service type SMS.",
                commonScripts: [
                    "sendByHandle": "tell application 'Messages' to send TEXT to participant HANDLE of (first service whose service type is iMessage)"
                ]
            ),
            "com.apple.mail": AppProfile(
                bundleID: "com.apple.mail",
                name: "Mail",
                strategy: .appleScript,
                instructions: "Standard Mail.app scripting suite supported.",
                commonScripts: [:]
            )
        ]
    }
    
    public func getProfile(for bundleID: String) -> AppProfile? {
        return registry[bundleID]
    }
    
    /// Bilinen tüm uygulamaların listesini döner (Discovery için temel)
    public func getAllKnownApps() -> [String] {
        return Array(registry.keys)
    }
    
    /// Ajanın bir uygulama hakkında 'akıl yürütmesi' için gereken ham bilgiyi döner.
    public func getKnowledgeSummary() -> String {
        var summary = "Core Application Intelligence (Titan Master Skills):\n"
        for (_, profile) in registry {
            summary += "- \(profile.name) (\(profile.bundleID)): \(profile.instructions) via \(profile.strategy.rawValue)\n"
        }
        return summary
    }
}
