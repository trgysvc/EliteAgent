import Foundation
import LocalAuthentication

/// SecuritySentinel, hassas işlemler (mesaj gönderme, silme vb.) öncesi Apple'ın biyometrik
/// güvenlik katmanını (TouchID/FaceID) veya kullanıcı parolasını doğrular.
public final class SecuritySentinel: Sendable {
    public static let shared = SecuritySentinel()
    
    private init() {}
    
    /// Kullanıcıdan biyometrik onay ister.
    /// - Parameter reason: Kullanıcıya gösterilecek onay gerekçesi.
    /// - Returns: Onay başarılıysa true, aksi halde false.
    @MainActor
    public func authenticateUser(reason: String) async -> Bool {
        let context = LAContext()
        var error: NSError?
        
        // Biyometrik (TouchID/FaceID) kullanılabilir mi kontrol et
        if context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error) {
            do {
                print("[SECURITY] Biyometrik doğrulama bekleniyor: \(reason) (Touch ID/Apple Watch)...")
                AgentLogger.logAudit(level: .info, agent: "SecuritySentinel", message: "Biometric authentication requested: \(reason)")
                return try await context.evaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, localizedReason: reason)
            } catch {
                print("[SecuritySentinel] Biyometrik doğrulama hatası: \(error.localizedDescription)")
                // Hata durumunda parolaya düş (Fallback)
                return await fallbackToPassword(context: context, reason: reason)
            }
        } else {
            // Biyometrik yoksa doğrudan cihaz parolasına düş
            return await fallbackToPassword(context: context, reason: reason)
        }
    }
    
    @MainActor
    private func fallbackToPassword(context: LAContext, reason: String) async -> Bool {
        do {
            return try await context.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: reason)
        } catch {
            print("[SecuritySentinel] Parola doğrulaması başarısız: \(error.localizedDescription)")
            return false
        }
    }
}
