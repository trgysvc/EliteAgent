import SwiftUI
import EliteAgentCore

struct AdvancedSettingsView: View {
    @StateObject private var modelManager = ModelManager.shared
    @State private var showingResetAlert = false
    @State private var modelDirSize: String = "Hesaplanıyor..."
    
    var body: some View {
        Form {
            // v9.0: Universal Model Management Section
            Section {
                Toggle("Model Geçişinde Otomatik Bellek Temizliği", isOn: $modelManager.isAutoUnloadEnabled)
                    .help("Default: ON. Yeni bir model yüklendiğinde eski modellerin VRAM'den otomatik silinmesini sağlar.")
                
                if !modelManager.isAutoUnloadEnabled {
                    Label("Uyarı: Birden fazla modeli yüklü tutmak sistem belleği (VRAM) üzerinde ciddi baskı oluşturabilir.", systemImage: "exclamationmark.triangle.fill")
                        .font(.caption2)
                        .foregroundStyle(.orange)
                }
                
                Divider()
                
                // v9.9.1: Stability Toggles
                Toggle("Stratejik Araştırma Modu (Deneysel)", isOn: Binding(
                    get: { UserDefaults.standard.bool(forKey: "enableResearchMode") },
                    set: { UserDefaults.standard.set($0, forKey: "enableResearchMode") }
                ))
                .help("Etkinleştirildiğinde, modelin ürettiği stratejik raporlar özel bir arayüz ile gösterilir.")
                
                Toggle("Parser Hata Ayıklama Günlükleri", isOn: Binding(
                    get: { UserDefaults.standard.bool(forKey: "debugParser") },
                    set: { UserDefaults.standard.set($0, forKey: "debugParser") }
                ))
                .font(.caption)
                .foregroundStyle(.secondary)
                
            } header: {
                Label("Model ve Sistem Yönetimi", systemImage: "cpu.fill")
            } footer: {
                Text("Cihazınız için önerilen: \(AutoConfigManager.shared.autoTune().preset == .performance ? "Performance Mode" : "Balanced Mode")")
            }
            
            Section {
                VStack(alignment: .leading, spacing: 12) {
                    Label("Fabrika Ayarlarına Dön", systemImage: "exclamationmark.shield.fill")
                        .font(.headline)
                        .foregroundStyle(.red)
                    
                    Text("Bu işlem; indirilen tüm yerel modelleri (\(modelDirSize)), keychain üzerindeki API anahtarlarınızı, günlük dosyalarını ve uygulama ayarlarını kalıcı olarak siler.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    
                    Button(role: .destructive) {
                        showingResetAlert = true
                    } label: {
                        Text("Her Şeyi Sil ve EliteAgent'ı Sıfırla")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.red)
                    .controlSize(.large)
                }
                .padding(.vertical, 8)
            } header: {
                Text("Kritik Alan")
            }
            
            Section {
                LabeledContent("Toplam Model Boyutu", value: modelDirSize)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } footer: {
                Text("Sıfırlama sonrası uygulama otomatik olarak kapatılacaktır. Yeniden başlatıldığında ilk kurulum ekranı belirecektir.")
            }
        }
        .formStyle(.grouped)
        .navigationTitle("Gelişmiş")
        .task {
            calculateSize()
        }
        .alert("Tüm Veriler Silinsin mi?", isPresented: $showingResetAlert) {
            Button("Vazgeç", role: .cancel) { }
            Button("Sıfırla ve Kapat", role: .destructive) {
                performFactoryReset()
            }
        } message: {
            Text("İndirilen modeller (\(modelDirSize)) dahil her şey silinecektir. Bu işlem geri alınamaz.")
        }
    }
    
    private func calculateSize() {
        let modelsURL = PathConfiguration.shared.modelsURL
        
        Task.detached(priority: .userInitiated) {
            guard FileManager.default.fileExists(atPath: modelsURL.path) else {
                await MainActor.run { self.modelDirSize = "0 GB" }
                return
            }
            
            var totalSize: Int64 = 0
            let modelSubDirs = (try? FileManager.default.contentsOfDirectory(at: modelsURL, includingPropertiesForKeys: [.fileSizeKey])) ?? []
            
            for subDir in modelSubDirs {
                let files = (try? FileManager.default.contentsOfDirectory(at: subDir, includingPropertiesForKeys: [.fileSizeKey])) ?? []
                for file in files {
                    if let attrs = try? file.resourceValues(forKeys: [.fileSizeKey]), let size = attrs.fileSize {
                        totalSize += Int64(size)
                    }
                }
            }
            
            let formatter = ByteCountFormatter()
            formatter.allowedUnits = [.useGB, .useMB]
            formatter.countStyle = .file
            let sizeString = formatter.string(fromByteCount: totalSize)
            await MainActor.run { self.modelDirSize = sizeString }
        }
    }
    
    private func performFactoryReset() {
        let appSupport = PathConfiguration.shared.applicationSupportURL
        let caches = PathConfiguration.shared.cachesURL
        let logs = PathConfiguration.shared.logsURL
        
        // 1. Wipe In-Memory State
        AISessionState.shared.selectedModel = ""
        AISessionState.shared.isInputLocked = false
        ModelManager.shared.loadedModels.removeAll()
        
        // 2. Wipe Local Filesystem (v14.0 SMART RESET: Does NOT touch Workspace in Documents)
        try? FileManager.default.removeItem(at: appSupport)
        try? FileManager.default.removeItem(at: caches)
        try? FileManager.default.removeItem(at: logs)
        
        // 3. Clear Keychain
        let keychain = KeychainHelper()
        let keysToClear = ["OPENROUTER_API_KEY", "HF_TOKEN", "com.eliteagent.api.figma", "BRAVE_API_KEY", "anthropic_api_key", "openai_api_key", "google_api_key"]
        for key in keysToClear {
            try? keychain.delete(key: key)
        }
        
        // 4. Clear UserDefaults
        if let bundleID = Bundle.main.bundleIdentifier {
            UserDefaults.standard.removePersistentDomain(forName: bundleID)
            UserDefaults.standard.synchronize()
        }
        
        exit(0)
    }
}
