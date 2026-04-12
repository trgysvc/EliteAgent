import SwiftUI
import EliteAgentCore

struct OnboardingWizardView: View {
    @Environment(\.dismiss) var dismiss
    @State private var currentPage = 1
    @State private var selectedProvider: String? = nil
    @State private var apiKey: String = ""
    @State private var ollamaStatus: String = "Denetleniyor..."
    @State private var progress: Double = 0.0
    @State private var statusText: String = ""
    @State private var errorMessage: String? = nil
    @ObservedObject var manager = ModelManager.shared
    
    var body: some View {
        VStack(spacing: 0) {
            if currentPage == 1 {
                page1Selection
            } else if currentPage == 2 {
                page2Setup
            } else {
                page3Ready
            }
        }
        .frame(width: 550, height: 450)
        .background(.ultraThinMaterial)
        .cornerRadius(20)
    }
    
    // MARK: - Page 1: Provider Selection
    private var page1Selection: some View {
        VStack(spacing: 24) {
            Text("🎉 EliteAgent'a Hoş Geldiniz!")
                .font(.system(size: 24, weight: .bold))
                .padding(.top, 32)
            
            Text("Nasıl çalışmak istersiniz?")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            
            HStack(spacing: 24) {
                providerCard(
                    id: "local",
                    title: "🏠 YEREL",
                    features: ["Cihazınızda çalışır (Privacy)", "Önerilen: Qwen 2.5", "M4 Air: ~45 tok/s"],
                    color: Color.accentColor,
                    action: { errorMessage = nil; selectedProvider = "local"; currentPage = 2; startLocalSetup() }
                )
                
                providerCard(
                    id: "cloud",
                    title: "☁️ CLOUD",
                    features: ["En güçlü modeller (Gemini)", "API Key gerekir", "İnternet bağlantısı şart"],
                    color: .orange,
                    action: { errorMessage = nil; selectedProvider = "cloud"; currentPage = 2 }
                )
            }
            .padding(.horizontal, 40)
            
            Button("⚙️ Sonra Ayarla") {
                UserDefaults.standard.set(true, forKey: "hasSkippedOnboarding")
                dismiss()
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            .padding(.bottom, 20)
            
            Spacer()
        }
    }
    
    // MARK: - Page 2: Dynamic Setup
    private var page2Setup: some View {
        VStack(spacing: 20) {
            Text(selectedProvider == "local" ? "Model Hazırlanıyor..." : "OpenRouter Kurulumu")
                .font(.title2.bold())
                .padding(.top, 32)
            
            if selectedProvider == "local" {
                VStack(spacing: 12) {
                    ProgressView(value: manager.downloadProgress.values.first ?? 0, total: 1.0)
                        .progressViewStyle(.linear)
                    Text(manager.downloadStatus.values.first ?? "Dosyalar kontrol ediliyor...")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    
                    Text("İndirme uygulama kapatılsa bile arka planda devam eder.")
                        .font(.system(size: 10))
                        .foregroundStyle(.tertiary)
                    
                    if (manager.downloadProgress.values.first ?? 0) >= 1.0 {
                        Button("Devam Et") { currentPage = 3 }
                            .buttonStyle(.borderedProminent)
                            .transition(.opacity)
                    }
                    
                    if errorMessage != nil {
                        Text(errorMessage!)
                            .font(.caption)
                            .foregroundStyle(.red)
                        Button("Tekrar Dene") { startLocalSetup() }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                    }
                }
                .padding(40)
            } else if selectedProvider == "cloud" {
                VStack(spacing: 16) {
                    TextField("OpenRouter API Key Girin", text: $apiKey)
                        .textFieldStyle(.roundedBorder)
                        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 8))
                    
                    Button("📥 Key Al (OpenRouter.ai)") {
                        if let url = URL(string: "https://openrouter.ai/keys") {
                            NSWorkspace.shared.open(url)
                        }
                    }
                    .buttonStyle(.link)
                    
                    Button("✅ Kaydet ve Devam") {
                        Task {
                            do {
                                let _ = try await OpenRouterProvider.shared.setupCloudProvider(apiKey: apiKey)
                                currentPage = 3
                            } catch {
                                errorMessage = "Geçersiz API Anahtarı. Lütfen kontrol edin."
                            }
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(apiKey.isEmpty)
                    
                    if errorMessage != nil {
                        Text(errorMessage!)
                            .font(.caption)
                            .foregroundStyle(.red)
                    }
                }
                .padding(40)
            }
            Spacer()
        }
    }
    
    // MARK: - Page 3: Ready
    private var page3Ready: some View {
        VStack(spacing: 24) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 64))
                .foregroundStyle(.green)
                .padding(.top, 40)
            
            Text("EliteAgent Hazır!")
                .font(.title.bold())
            
            VStack(alignment: .leading, spacing: 12) {
                Text("💡 İpuçları:")
                    .font(.headline)
                Label("Model değiştirmek: Üst menüyü kullan", systemImage: "sparkles")
                Label("Yeni sohbet: ⌘N kısayolunu hatırla", systemImage: "command")
                Label("Ayarlar: ⌘, ile gizliliği yönet", systemImage: "gearshape")
            }
            .padding()
            .background(.secondary.opacity(0.1), in: RoundedRectangle(cornerRadius: 12))
            
            Button("💬 Sohbet Et") { dismiss() }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
            
            Spacer()
        }
    }
    
    // MARK: - Subviews
    private func providerCard(id: String, title: String, features: [String], color: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 10) {
                Text(title)
                    .font(.headline)
                    .foregroundStyle(color)
                
                ForEach(features, id: \.self) { feature in
                    Text("• \(feature)")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.leading)
                }
                Spacer()
            }
            .padding()
            .frame(maxWidth: .infinity, maxHeight: 180)
            .background(.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 16))
            .overlay(RoundedRectangle(cornerRadius: 16).stroke(color.opacity(0.3), lineWidth: 1))
        }
        .buttonStyle(.plain)
    }
    
    private func startLocalSetup() {
        errorMessage = nil
        Task {
            do {
                try await manager.setupLocalProvider()
            } catch {
                errorMessage = "İndirme başlatılamadı veya donanım uyumsuz. Lütfen bağlantınızı kontrol edin."
            }
        }
    }
}
