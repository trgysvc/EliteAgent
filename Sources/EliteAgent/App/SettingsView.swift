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
                Label("Data & Privacy", systemImage: "hand.raised.fill").tag("Privacy")
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
                case "Privacy":
                    DataPrivacySettingsView(orchestrator: orchestrator)
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
struct DataPrivacySettingsView: View {
    @ObservedObject var orchestrator: Orchestrator
    @State private var showingClearAlert = false
    
    var body: some View {
        Form {
            Section("Chat History") {
                Text("Your chat history is stored locally on this Mac. Clearing it will permanently remove all past conversations and agent experiences.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                
                Button(role: .destructive) {
                    showingClearAlert = true
                } label: {
                    Label("Clear All Chat History", systemImage: "trash")
                }
            }
            
            Section("Local Storage") {
                LabeledContent("Storage Location", value: "~/.eliteagent/history.json")
            }
        }
        .formStyle(.grouped)
        .navigationTitle("Data & Privacy")
        .alert("Clear History?", isPresented: $showingClearAlert) {
            Button("Cancel", role: .cancel) { }
            Button("Clear Everything", role: .destructive) {
                Task {
                    await orchestrator.clearAllHistory()
                }
            }
        } message: {
            Text("This action cannot be undone. All your past conversations will be permanently deleted.")
        }
    }
}
