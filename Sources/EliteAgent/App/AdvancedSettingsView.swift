import SwiftUI
import EliteAgentCore

struct AdvancedSettingsView: View {
    @State private var showingResetAlert = false
    @State private var modelDirSize: String = "Hesaplanıyor..."
    
    var body: some View {
        Form {
            Section {
                VStack(alignment: .leading, spacing: 12) {
                    Label("Fabrika Ayarlarına Dön", systemImage: "exclamationmark.shield.fill")
                        .font(.headline)
                        .foregroundStyle(.red)
                    
                    Text("Bu işlem; indirilen tüm yerel modelleri (\(modelDirSize)), keychain üzerindeki API anahtarlarınızı ve uygulama ayarlarını kalıcı olarak siler.")
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
                LabeledContent("Model Depolama", value: modelDirSize)
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
        let appSupport = PathConfiguration.shared.applicationSupportURL
        let modelsURL = appSupport.appendingPathComponent("Models")
        
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
        
        // 1. Wipe In-Memory State
        AISessionState.shared.selectedModel = ""
        AISessionState.shared.isInputLocked = false
        ModelSetupManager.shared.activeModelID = ""
        ModelSetupManager.shared.isModelReady = false
        ModelSetupManager.shared.state = .idle
        
        // 2. Wipe Local Filesystem
        try? FileManager.default.removeItem(at: appSupport)
        try? FileManager.default.removeItem(at: caches)
        
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
