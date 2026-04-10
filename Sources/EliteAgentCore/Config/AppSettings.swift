import Foundation
import Combine

/// AppSettings, EliteAgent'ın kullanıcı tercihlerini (Biyometrik güvenlik, tema vb.)
/// UserDefaults kullanarak kalıcı olarak saklar ve SwiftUI görünümlerine yayınlar.
@MainActor
public final class AppSettings: ObservableObject, Sendable {
    public static let shared = AppSettings()
    
    /// Uygulama her açıldığında TouchID/Parola sorulup sorulmayacağı.
    @Published public var isBiometricEnabledForStartup: Bool {
        didSet {
            UserDefaults.standard.set(isBiometricEnabledForStartup, forKey: "isBiometricEnabledForStartup")
        }
    }
    
    /// Hassas işlemler (Mesaj gönderimi, silme vb.) öncesi TouchID sorulup sorulmayacağı.
    @Published public var isBiometricEnabledForActions: Bool {
        didSet {
            UserDefaults.standard.set(isBiometricEnabledForActions, forKey: "isBiometricEnabledForActions")
        }
    }
    
    /// Yapay zeka çalışırken arka plan seslerini kısıp kısmayacağı (Focus Mode).
    @Published public var isQuietModeEnabled: Bool {
        didSet {
            UserDefaults.standard.set(isQuietModeEnabled, forKey: "isQuietModeEnabled")
        }
    }
    
    private init() {
        // v13.9: Sensitive actions default to SECURE (true)
        if UserDefaults.standard.object(forKey: "isBiometricEnabledForActions") == nil {
            UserDefaults.standard.set(true, forKey: "isBiometricEnabledForActions")
        }
        
        self.isBiometricEnabledForStartup = UserDefaults.standard.bool(forKey: "isBiometricEnabledForStartup")
        self.isBiometricEnabledForActions = UserDefaults.standard.bool(forKey: "isBiometricEnabledForActions")
        self.isQuietModeEnabled = UserDefaults.standard.bool(forKey: "isQuietModeEnabled")
    }
}
