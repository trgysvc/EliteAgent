import SwiftUI
import EliteAgentCore

/// SettingsView, yan menülü (Sidebar) yapıda modern bir ayarlar arayüzü sunar.
/// Kullanıcının güvenlik, genel ve yapay zekâ tercihlerini yönetmesini sağlar.
public struct SettingsView: View {
    @ObservedObject var orchestrator: Orchestrator
    @ObservedObject var modelPickerVM: ModelPickerViewModel
    @State private var selection: String? = "General"
    @State private var showingTitanSetup = false
    @Environment(\.dismiss) var dismiss
    
    public init(orchestrator: Orchestrator, modelPickerVM: ModelPickerViewModel) {
        self.orchestrator = orchestrator
        self.modelPickerVM = modelPickerVM
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
                    AISettingsView(modelPickerVM: modelPickerVM, showingTitanSetup: $showingTitanSetup)
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
        .sheet(isPresented: $showingTitanSetup) {
            ModelSetupView()
        }
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
    @ObservedObject var modelPickerVM: ModelPickerViewModel
    @Binding var showingTitanSetup: Bool
    
    // v7.8.0 Centralized State
    @State private var sessionState = AISessionState.shared
    
    var body: some View {
        Form {
            Section("Aktif Zeka Modeli") {
                if let selected = modelPickerVM.selected {
                    HStack(spacing: 12) {
                        Image(systemName: selected.icon)
                            .font(.title)
                            .foregroundStyle(Color.accentColor)
                        
                        VStack(alignment: .leading) {
                            Text(selected.name)
                                .font(.headline)
                            Text(selected.id)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        
                        Spacer()
                        
                        if case .localMLX = selected {
                           Text("Hardware Accelerated")
                                .font(.caption2.bold())
                                .padding(4)
                                .background(.green.opacity(0.1), in: Capsule())
                                .foregroundStyle(.green)
                        } else {
                            Text("Cloud Reasoning")
                                .font(.caption2.bold())
                                .padding(4)
                                .background(.blue.opacity(0.1), in: Capsule())
                                .foregroundStyle(.blue)
                        }
                    }
                    .padding(.vertical, 8)
                } else {
                    Text("Model Seçilmedi")
                        .foregroundStyle(.secondary)
                }
            }
            
            Section("Inference Engine Status") {
                HStack {
                    Label("Active Provider", systemImage: "server.rack")
                    Spacer()
                    Text(sessionState.activeProvider)
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(sessionState.isFallbackActive ? .orange : .accentColor)
                }
                
                if sessionState.isFallbackActive {
                    HStack {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange)
                        Text("Cloud Fallback Active: Local engine failover triggered.")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            
            Section("Inference Analytics (v7.8.5)") {
                LabeledContent("Last Latency") {
                    Text(String(format: "%.2fs", sessionState.lastInferenceLatency))
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(sessionState.lastInferenceLatency > 5 ? Color.orange : Color.primary)
                }
                
                LabeledContent("Throughput") {
                    Text(String(format: "%.1f t/s", sessionState.tokensPerSecond))
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(sessionState.tokensPerSecond < 10 ? Color.secondary : Color.green)
                }
                
                LabeledContent("Cloud Fallbacks") {
                    HStack {
                        Text("\(sessionState.fallbackCount)")
                        if sessionState.fallbackCount > 0 {
                            Button("Reset") { sessionState.fallbackCount = 0 }
                                .buttonStyle(.plain)
                                .font(.caption2)
                                .foregroundStyle(.blue)
                        }
                    }
                }
            }
            
            Section("Fallback Policy") {
                Picker("Hata Politika Yönetimi", selection: $sessionState.fallbackPolicy) {
                    Text("Always Prompt (Safe)").tag(FallbackPolicy.promptBeforeSwitch)
                    Text("Strict Local (No Cloud)").tag(FallbackPolicy.strictLocal)
                    Text("Auto Fallback (Silent)").tag(FallbackPolicy.autoSwitchWithBadge)
                }
                .pickerStyle(.menu)
                .help("Yerel model çalışmadığında sistemin nasıl davranacağını belirler.")
                
                Text(policyExplanation)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            
            Section("Yüklü Yerel Modeller (Titan)") {
                let installed = modelPickerVM.installedLocalModels
                if installed.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Henüz yerel model indirilmedi.")
                            .foregroundStyle(.secondary)
                        Button("Titan Kurulum Sihirbazını Başlat") {
                            showingTitanSetup = true
                        }
                        .buttonStyle(.link)
                    }
                } else {
                    List {
                        ForEach(installed) { model in
                            HStack {
                                Label(model.name, systemImage: "cpu.fill")
                                Spacer()
                                Text("Ready")
                                    .font(.caption2)
                                    .foregroundStyle(.green)
                            }
                        }
                    }
                    .frame(minHeight: 100)
                }
            }
            
            Section("Yapılandırma & Araçlar") {
                Button {
                    openVaultConfig()
                } label: {
                    Label("Provider Seçeneklerini Düzenle (Vault)", systemImage: "doc.text.fill")
                }
                .help("vault.plist dosyasını açarak API anahtarlarınızı ve model uç noktalarını düzenleyebilirsiniz.")
                
                Button {
                    openModelsFolder()
                } label: {
                    Label("Model Klasörünü Aç", systemImage: "folder.fill")
                }
                .help("İndirilen model ağırlıklarını yönetmek için Models klasörünü açar.")
                
                Button {
                    showingTitanSetup = true
                } label: {
                    Label("Titan Kurulum Sihirbazı", systemImage: "wand.and.stars")
                }
            }
        }
        .formStyle(.grouped)
        .navigationTitle("Yapay Zekâ Ayarları")
    }
    
    private var policyExplanation: String {
        switch sessionState.fallbackPolicy {
        case .promptBeforeSwitch: return "Önerilen: Yerel model hata verirse buluta geçmeden önce onayınızı ister."
        case .strictLocal: return "Güvenli: Bulut servislerine geçişi tamamen engeller. Hata durumunda işlem durur."
        case .autoSwitchWithBadge: return "Hızlı: Kesintisiz deneyim için otomatik buluta geçer, küçük bir rozetle uyarır."
        }
    }

    private func openVaultConfig() {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let vaultURL = appSupport.appendingPathComponent("EliteAgent/vault.plist")
        NSWorkspace.shared.open(vaultURL)
    }
    
    private func openModelsFolder() {
        let modelsURL = ModelSetupManager.shared.getModelDirectory().deletingLastPathComponent()
        NSWorkspace.shared.open(modelsURL)
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
                LabeledContent("History Data", value: "~/Library/Application Support/EliteAgent/history.json")
                LabeledContent("Vault Config", value: "~/Library/Application Support/EliteAgent/vault.plist")
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
