import Foundation

public enum AppleScriptError: Error, Sendable {
    case initializationFailed
    case executionFailed(String)
}

public actor AppleScriptRunner {
    public static let shared = AppleScriptRunner()
    
    private init() {}
    
    public func execute(source: String) async throws -> String {
        guard let script = NSAppleScript(source: source) else {
            throw AppleScriptError.initializationFailed
        }
        
        var errorDict: NSDictionary?
        let result = script.executeAndReturnError(&errorDict)
        
        if let error = errorDict {
            let message = error["NSAppleScriptErrorMessage"] as? String ?? "Unknown AppleScript error"
            let errorCode = error["NSAppleScriptErrorNumber"] as? Int ?? -1
            
            var diagnostic = "AppleScript Error \(errorCode): \(message)"
            
            // v9.4: Extract targetApp for better diagnostics
            let targetApp = ["Music", "WhatsApp", "Contacts", "Messages", "Safari", "Finder", "System Events"].first(where: { source.contains("application \"\($0)\"") }) ?? "Hedef Uygulama"
            
            if errorCode == -1743 {
                diagnostic += "\n[DIAGNOSTIC] EliteAgent'ın \(targetApp) kontrol yetkisi yok. Lütfen Sistem Ayarları > Gizlilik ve Güvenlik > Otomasyon kısmından EliteAgent'a izin verin."
                AgentLogger.logAudit(level: .warn, agent: "AppleScript", message: "⚠️ Permission denied for \(targetApp). errorCode: -1743")
                
                // v9.4: Trigger UI Alert via AISessionState
                Task { @MainActor in
                    AISessionState.shared.permissionAppTarget = targetApp
                    AISessionState.shared.requiresPermissionAcknowledgement = true
                }
            } else if errorCode == -43 {
                diagnostic += "\n[DIAGNOSTIC] \(targetApp) veya dosya bulunamadı. Lütfen uygulamanın yüklü olduğundan emin olun."
            } else if errorCode == -1728 || errorCode == 0 {
                diagnostic += "\n[DIAGNOSTIC] Sistemsel engel veya protokol hatası. Lütfen Sistem Ayarları > Gizlilik ve Güvenlik > Otomasyon kısmını kontrol edin."
            }
            
            print("[ORCHESTRATOR] \(diagnostic)")
            throw AppleScriptError.executionFailed(diagnostic)
        }
        
        return result.stringValue ?? ""
    }
}
