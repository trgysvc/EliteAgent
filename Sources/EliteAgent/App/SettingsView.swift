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
                Label("Veri ve Gizlilik", systemImage: "hand.raised.fill").tag("Privacy")
                Label("Sistem Sağlığı", systemImage: "bolt.heart.fill").tag("Health")
                Label("Gelişmiş", systemImage: "bolt.shield.fill").tag("Advanced")
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
                case "Tools":
                    ToolsSettingsView()
                case "Analytics":
                    UsageDashboardView(orchestrator: orchestrator)
                case "Privacy":
                    DataPrivacySettingsView(orchestrator: orchestrator)
                case "Health":
                    LLMHealthDashboardView()
                case "Advanced":
                    AdvancedSettingsView()
                default:
                    ContentUnavailableView("Seçim Yapın", systemImage: "sidebar.left")
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
                    .font(.footnote)
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
                Toggle("Hassas İşlemlerde Onay İste", isOn: $settings.isBiometricEnabledForActions)
            }
            
            Section {
                Text("Biyometrik verileriniz Apple'ın güvenli Secure Enclave katmanında saklanır.")
                    .font(.footnote)
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
    @State private var sessionState = AISessionState.shared
    @State private var openRouterKey: String = ""
    @State private var isSavingKey: Bool = false
    
    private let vaultURL = PathConfiguration.shared.vaultURL
    
    var body: some View {
        Form {
            Section("Aktif Zeka Modeli") {
                if let selected = modelPickerVM.selected {
                    HStack(spacing: 12) {
                        Image(systemName: selected.icon)
                            .font(.title2)
                            .foregroundStyle(Color.accentColor)
                        
                        VStack(alignment: .leading, spacing: 2) {
                            Text(selected.name)
                                .font(.headline)
                            Text(selected.id)
                                .font(.caption.monospaced())
                                .foregroundStyle(.secondary)
                        }
                        
                        Spacer()
                        
                        Text(caseLocalOrCloud(selected))
                            .font(.caption2.bold())
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(caseLocalOrCloud(selected) == "HIZLANDIRILMIŞ" ? Color.green.opacity(0.1) : Color.blue.opacity(0.1), in: Capsule())
                            .foregroundStyle(caseLocalOrCloud(selected) == "HIZLANDIRILMIŞ" ? .green : .blue)
                    }
                    .padding(.vertical, 4)
                } else {
                    Text("Model Seçilmedi")
                        .foregroundStyle(.secondary)
                }
            }
            
            Section("Motor Durumu") {
                LabeledContent("Aktif Sağlayıcı", value: sessionState.activeProvider)
                
                if sessionState.isFallbackActive {
                    Label("Bulut Fallback Aktif", systemImage: "exclamationmark.triangle.fill")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
            }
            
            Section("Analizler (v7.9.0)") {
                LabeledContent("Gecikme") {
                    Text(String(format: "%.2fs", sessionState.lastInferenceLatency))
                        .foregroundStyle(sessionState.lastInferenceLatency > 5 ? .orange : .primary)
                }
                
                LabeledContent("Hız (Token/s)") {
                    Text(String(format: "%.1f", sessionState.tokensPerSecond))
                        .foregroundStyle(sessionState.tokensPerSecond < 10 ? Color.secondary : Color.green)
                }
                
                LabeledContent("Yönlendirme Sayısı") {
                    HStack {
                        Text("\(sessionState.fallbackCount)")
                        if sessionState.fallbackCount > 0 {
                            Button("Sıfırla") { sessionState.fallbackCount = 0 }
                                .buttonStyle(.borderless)
                                .controlSize(.mini)
                        }
                    }
                }
            }
            
            Section("Hata Politikası") {
                Picker("Politika", selection: $sessionState.fallbackPolicy) {
                    Text("Her Zaman Sor (Güvenli)").tag(FallbackPolicy.promptBeforeSwitch)
                    Text("Sadece Yerel (Katı)").tag(FallbackPolicy.strictLocal)
                    Text("Otomatik Geçiş (Hızlı)").tag(FallbackPolicy.autoSwitchWithBadge)
                }
                .pickerStyle(.menu)
            }
            
            Section("Kimlik Doğrulama") {
                HStack {
                    Image(systemName: "key.horizontal.fill")
                        .foregroundStyle(.secondary)
                    
                    SecureField("OpenRouter API Key", text: $openRouterKey)
                        .textFieldStyle(.plain)
                    
                    if isSavingKey {
                        ProgressView().controlSize(.mini)
                    } else {
                        Button("Kaydet") {
                            saveOpenRouterKey()
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)
                        .disabled(openRouterKey.isEmpty)
                    }
                }
                
                Text("OpenRouter modellerini kullanabilmek için geçerli bir API anahtarı gereklidir. Anahtarınız macOS Keychain (Anahtar Zinciri) üzerinde güvenli bir şekilde saklanır.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            
            Section("Yapılandırma") {
                Button { openVaultConfig() } label: {
                    Label("API Anahtarlarını Düzenle (Vault)", systemImage: "key.fill")
                }
                Button { openModelsFolder() } label: {
                    Label("Model Klasörünü Aç", systemImage: "folder.fill")
                }
                Button { showingTitanSetup = true } label: {
                    Label("Titan Kurulum Sihirbazı", systemImage: "wand.and.stars")
                }
            }
        }
        .formStyle(.grouped)
        .navigationTitle("Yapay Zekâ Ayarlar")
        .onAppear {
            loadExistingKey()
        }
    }
    
    private func loadExistingKey() {
        Task {
            do {
                let vault = try VaultManager(configURL: vaultURL)
                // Use the matching ID from VaultManager.syncRequiredProviders
                if let openRouterProv = vault.config.providers.first(where: { $0.id == "openrouter" }) {
                    let key = try await vault.getAPIKey(for: openRouterProv)
                    await MainActor.run {
                        self.openRouterKey = key
                    }
                }
            } catch {
                print("[AISettings] No existing OpenRouter key found or failed to read: \(error)")
            }
        }
    }
    
    private func saveOpenRouterKey() {
        isSavingKey = true
        Task {
            do {
                let vault = try VaultManager(configURL: vaultURL)
                try await vault.updateAPIKey(for: "openrouter", token: openRouterKey)
                
                // v7.8.9: Force ModelPicker re-discovery
                NotificationCenter.default.post(name: NSNotification.Name("CredentialsUpdated"), object: nil)
                
                await MainActor.run {
                    isSavingKey = false
                }
            } catch {
                print("[AISettings] Failed to save OpenRouter key: \(error)")
                await MainActor.run {
                    isSavingKey = false
                }
            }
        }
    }
    
    private func caseLocalOrCloud(_ selected: ModelSource) -> String {
        if case .localMLX = selected { return "HIZLANDIRILMIŞ" }
        return "BULUT"
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
            Section {
                Text("Chat geçmişiniz yerel olarak Mac'inizde saklanır. Silme işlemi tüm geçmişi kalıcı olarak temizler.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } header: {
                Text("Geçmiş Verileri")
            }
            
            Section {
                Button(role: .destructive) {
                    showingClearAlert = true
                } label: {
                    Label("Tüm Sohbet Geçmişini Sil", systemImage: "trash")
                }
                .frame(maxWidth: .infinity, alignment: .center)
            }
            
            Section("Konum Bilgisi") {
                LabeledContent("Geçmiş Dosyası", value: "history.json")
                LabeledContent("Güvenli Kasa", value: "vault.plist")
            }
        }
        .formStyle(.grouped)
        .navigationTitle("Veri ve Gizlilik")
        .alert("Geçmişi Sil?", isPresented: $showingClearAlert) {
            Button("Vazgeç", role: .cancel) { }
            Button("Her Şeyi Sil", role: .destructive) {
                Task { await orchestrator.clearAllHistory() }
            }
        } message: {
            Text("Bu işlem geri alınamaz. Tüm konuşmalarınız kalıcı olarak silinecektir.")
        }
    }
}
