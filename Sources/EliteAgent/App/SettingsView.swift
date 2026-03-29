import SwiftUI
import EliteAgentCore

/// SettingsView, yan menülü (Sidebar) yapıda modern bir ayarlar arayüzü sunar.
/// Kullanıcının güvenlik, genel ve yapay zekâ tercihlerini yönetmesini sağlar.
public struct SettingsView: View {
    @ObservedObject var orchestrator: Orchestrator
    @State private var selection: String? = "General"
    @Environment(\.dismiss) var dismiss
    
    public init(orchestrator: Orchestrator) {
        self.orchestrator = orchestrator
    }
    
    public var body: some View {
        NavigationSplitView {
            List(selection: $selection) {
                Label("Genel", systemImage: "gear").tag("General")
                Label("Güvenlik", systemImage: "lock.shield").tag("Security")
                Label("Yapay Zekâ", systemImage: "sparkles").tag("AI")
                Label("Analizler", systemImage: "chart.bar.xaxis").tag("Analytics")
            }
            .navigationTitle("Ayarlar")
        } detail: {
            Group {
                switch selection {
                case "General":
                    GeneralSettingsView()
                case "Security":
                    SecuritySettingsView()
                case "AI":
                    AISettingsView()
                case "Analytics":
                    UsageDashboardView(orchestrator: orchestrator)
                default:
                    Text("Bir kategori seçiniz")
                }
            }
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Kapat") {
                        dismiss()
                    }
                }
            }
        }
        .frame(minWidth: 650, minHeight: 450)
    }
}

struct GeneralSettingsView: View {
    @ObservedObject var settings = AppSettings.shared
    
    var body: some View {
        Form {
            Section("Uygulama Bilgileri") {
                LabeledContent("Versiyon", value: "1.2.0 (Build 42)")
                LabeledContent("Geliştirici", value: "Turgay Savacı")
            }
            
            Section("Odaklanma") {
                Toggle("Sessiz Çalışma Modu", isOn: $settings.isQuietModeEnabled)
                    .help("Yapay zeka işlem yaparken arka plan seslerini otomatik olarak kısar.")
            }
            
            Section("Görünüm") {
                Text("Tematik ayarlar ve arayüz özelleştirmeleri yakında eklenecektir.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .navigationTitle("Genel Ayarlar")
    }
}

struct SecuritySettingsView: View {
    @ObservedObject var settings = AppSettings.shared
    
    var body: some View {
        Form {
            Section("Biyometrik Güvenlik (TouchID)") {
                Toggle("Uygulama Açılışında Doğrula", isOn: $settings.isBiometricEnabledForStartup)
                    .help("Uygulama her açıldığında TouchID veya parola ister.")
                
                Toggle("Hassas İşlemlerde Onay İste", isOn: $settings.isBiometricEnabledForActions)
                    .help("Mesaj gönderimi, dosya silme gibi kritik işlemlerde parmak izi onayı ister.")
            }
            
            Section("Bilgilendirme") {
                Text("Biyometrik verileriniz Apple'ın güvenli Secure Enclave katmanında saklanır. EliteAgent bu verilere asla doğrudan erişemez.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .navigationTitle("Güvenlik Ayarları")
    }
}

struct AISettingsView: View {
    var body: some View {
        Form {
            Section("Model Yönetimi") {
                Text("Mevcut Modeller: MLX (Yerel), OpenRouter (Bulut)")
                Button("Model Ayarlarını Düzenle") {
                    // Gelecekte model ekleme/çıkarma buraya bağlanabilir
                }
            }
        }
        .formStyle(.grouped)
        .navigationTitle("Yapay Zekâ Ayarları")
    }
}
