import SwiftUI
import EliteAgentCore

/// Premium Setup Assistant for the Titan Engine (Local MLX Intelligence).
/// Refined for Apple HIG alignment with high-performance standards (v7.9.0).
public struct ModelSetupView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var manager = ModelSetupManager.shared
    @State private var setupPhase: Int = 0 
    
    // Deletion & Modal States
    @State private var modelToDelete: String?
    @State private var isDeleting = false
    @State private var deleteError: String?
    @State private var cachedModelSize: String?
    @State private var selectedQuant: String = "Q5_K_M"
    
    public init() {}
    
    public var body: some View {
        ZStack {
            // Adaptive Background (Sequoia Style)
            Rectangle()
                .fill(.ultraThinMaterial)
                .ignoresSafeArea()
            
            // Subtle Radial Accent
            RadialGradient(
                colors: [.accentColor.opacity(0.1), .clear],
                center: .topTrailing,
                startRadius: 0,
                endRadius: 600
            )
            .ignoresSafeArea()
            
            VStack(spacing: 32) {
                // Header
                headerView
                
                // Content Switcher
                Group {
                    if manager.isModelReady {
                        successPhase
                    } else if setupPhase == 0 {
                        welcomePhase
                    } else {
                        instructionsPhase
                    }
                }
                .transition(.asymmetric(insertion: .push(from: .bottom), removal: .opacity))
                
                Spacer()
                
                // Footer
                footerView
            }
            .padding(40)
        }
        .frame(width: 520, height: 640)
        .animation(.spring(response: 0.4, dampingFraction: 0.8), value: setupPhase)
        .alert("Model dosyalarını sil?", isPresented: Binding(
            get: { modelToDelete != nil },
            set: { if !$0 { modelToDelete = nil; cachedModelSize = nil } }
        )) {
            Button("Vazgeç", role: .cancel) { }
            Button("Sil", role: .destructive) {
                if let id = modelToDelete { deleteModel(id) }
            }
        } message: {
            Text("Seçilen model (\(cachedModelSize ?? "")) silinecektir. Bu işlem geri alınamaz.")
        }
    }
    
    private func deleteModel(_ id: String) {
        isDeleting = true
        Task {
            do {
                try await manager.deleteModel(id)
                await MainActor.run {
                    isDeleting = false
                    modelToDelete = nil
                }
            } catch {
                await MainActor.run {
                    deleteError = error.localizedDescription
                    isDeleting = false
                }
            }
        }
    }
    
    // MARK: - Components
    
    private var headerView: some View {
        VStack(spacing: 12) {
            Image(systemName: "cpu.fill")
                .font(.system(size: 48, weight: .bold))
                .foregroundStyle(.linearGradient(colors: [.accentColor, .blue], startPoint: .top, endPoint: .bottom))
                .symbolEffect(.pulse)
            
            Text("Elite Titan Motoru")
                .font(.title.bold())
                .foregroundStyle(.primary)
            
            Text("Hibrit Zeka Aktivasyonu")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
    }
    
    private var welcomePhase: some View {
        VStack(spacing: 24) {
            Text("Mac'inizin gücünü yerel Apple Silicon yapay zekası ile birleştirin.")
                .font(.body)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 20)
            
            VStack(alignment: .leading, spacing: 16) {
                featureRow(icon: "lock.shield", title: "%100 Gizli", desc: "Verileriniz asla cihazınızdan çıkmaz.")
                featureRow(icon: "bolt.fill", title: "Metal Optimizasyonu", desc: "Native M-serisi GPU hızlandırması.")
                featureRow(icon: "wifi.slash", title: "Çevrimdışı Kullanım", desc: "İnternet bağlantısı olmadan tam performans.")
            }
            .padding(20)
            .background(.primary.opacity(0.03), in: RoundedRectangle(cornerRadius: 18))
        }
    }
    
    private var instructionsPhase: some View {
        VStack(spacing: 24) {
            if manager.isDownloading {
                // DOWNLOAD PROGRESS
                VStack(spacing: 20) {
                    Text("İndiriliyor...")
                        .font(.headline)
                    
                    ProgressView(value: manager.downloadProgress)
                        .progressViewStyle(.linear)
                        .tint(.accentColor)
                        .scaleEffect(x: 1, y: 1.5, anchor: .center)
                    
                    Text("\(Int(manager.downloadProgress * 100))%")
                        .font(.title2.bold().monospacedDigit())
                        .foregroundStyle(.secondary)
                }
                .padding(30)
                .background(.background.opacity(0.4), in: RoundedRectangle(cornerRadius: 24))
            } else {
                // MODEL SELECTION
                VStack(spacing: 20) {
                    modelSelectionCard(
                        id: "Qwen2.5-7B-Instruct-4bit",
                        title: "Titan Dengeli (v1)",
                        desc: "Qwen 2.5 7B. Hızlı, 8GB RAM uyumlu.",
                        badge: "4.5 GB"
                    )
                    
                    modelSelectionCard(
                        id: "Qwen3.5-9B-4bit",
                        title: "Titan Güçlü (v2)",
                        desc: "Qwen 3.5 9B. Üstün akıl yürütme, 16GB RAM önerilir.",
                        badge: "6.2 GB",
                        isPremium: true
                    )
                    
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Hassasiyet (Quantization)")
                            .font(.caption.bold())
                            .foregroundStyle(.secondary)
                        
                        Picker("", selection: $selectedQuant) {
                            Text("Hızlı (Q4)").tag("Q4_K_M")
                            Text("Dengeli (Q5)").tag("Q5_K_M")
                            Text("Net (Q8)").tag("Q8_0")
                        }
                        .pickerStyle(.segmented)
                    }
                    .padding(.top, 8)
                }
            }
        }
    }
    
    private func modelSelectionCard(id: String, title: String, desc: String, badge: String, isPremium: Bool = false) -> some View {
        Button {
            manager.activeModelID = id
        } label: {
            HStack(spacing: 16) {
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(title).font(.body.bold())
                        if isPremium {
                            Text("YENİ")
                                .font(.system(size: 8, weight: .black))
                                .padding(.horizontal, 4).padding(.vertical, 2)
                                .background(.blue, in: RoundedRectangle(cornerRadius: 4))
                                .foregroundStyle(.white)
                        }
                    }
                    Text(desc).font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                
                if manager.isModelAvailable(id) {
                    Button(role: .destructive) {
                        modelToDelete = id
                        Task { cachedModelSize = await manager.modelSize(for: id) }
                    } label: {
                        Image(systemName: "trash").foregroundStyle(.red)
                    }.buttonStyle(.plain)
                }
                
                Image(systemName: manager.activeModelID == id ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(manager.activeModelID == id ? Color.accentColor : Color.secondary)
            }
            .padding()
            .background(manager.activeModelID == id ? Color.accentColor.opacity(0.1) : Color.primary.opacity(0.02))
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .stroke(manager.activeModelID == id ? Color.accentColor : Color.primary.opacity(0.1), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }
    
    private var successPhase: some View {
        VStack(spacing: 24) {
            Image(systemName: "checkmark.seal.fill")
                .font(.system(size: 72))
                .foregroundStyle(.green)
                .symbolEffect(.bounce, value: manager.isModelReady)
            
            Text("Titan Devreye Alındı")
                .font(.title2.bold())
            
            Text("Yerel yapay zeka motoru GPU üzerinde çalışmaya hazır.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
    }
    
    private var footerView: some View {
        HStack {
            if manager.isModelReady {
                Button { dismiss() } label: {
                    Text("Sohbete Başla")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
            } else if !manager.isDownloading {
                if setupPhase == 0 {
                    Button("Kuruluma Başla") {
                        withAnimation { setupPhase = 1 }
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .frame(maxWidth: .infinity)
                } else {
                    Button("Vazgeç") { dismiss() }
                        .buttonStyle(.plain).foregroundStyle(.secondary)
                    
                    Spacer()
                    
                    Button("Modeli İndir") {
                        manager.startModelDownload()
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(manager.activeModelID.isEmpty)
                }
            }
        }
    }
    
    private func featureRow(icon: String, title: String, desc: String) -> some View {
        HStack(spacing: 16) {
            Image(systemName: icon)
                .font(.title3)
                .frame(width: 32)
                .foregroundStyle(Color.accentColor)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.headline)
                Text(desc).font(.caption).foregroundStyle(.secondary)
            }
        }
        .accessibilityElement(children: .combine)
    }
}
