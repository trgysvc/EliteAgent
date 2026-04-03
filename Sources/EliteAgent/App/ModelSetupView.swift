import SwiftUI
import EliteAgentCore

/// Premium Setup Assistant for the Titan Engine (Local MLX Intelligence).
public struct ModelSetupView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var manager = ModelSetupManager.shared
    @State private var setupPhase: Int = 0 
    
    // Deletion State
    @State private var modelToDelete: String?
    @State private var isDeleting = false
    @State private var deleteError: String?
    @State private var cachedModelSize: String?
    
    // v7.8.0 Credentials & Choice
    @State private var hfToken: String = ""
    @State private var selectedQuant: String = "Q5_K_M"
    
    public init() {}
    
    public var body: some View {
        ZStack {
            // Background
            Color.black.ignoresSafeArea()
            
            // Subtle Radial Gradient for "Titan" feel
            RadialGradient(
                colors: [Color.blue.opacity(0.15), Color.clear],
                center: .center,
                startRadius: 0,
                endRadius: 500
            )
            .ignoresSafeArea()
            
            VStack(spacing: 24) {
                // Header
                headerView
                
                // Content Switcher
                if manager.isModelReady {
                    successPhase
                } else if setupPhase == 0 {
                    welcomePhase
                } else {
                    instructionsPhase
                }
                
                Spacer()
                
                // Footer
                footerView
            }
            .padding(40)
        }
        .frame(width: 500, height: 600)
        .alert("Modeli Sil", isPresented: Binding(
            get: { modelToDelete != nil },
            set: { if !$0 { modelToDelete = nil; cachedModelSize = nil } }
        )) {
            Button("İptal", role: .cancel) { modelToDelete = nil; cachedModelSize = nil }
            Button("Sil", role: .destructive) {
                guard let id = modelToDelete else { return }
                deleteModel(id)
            }
        } message: {
            if isDeleting {
                Text("Model dosyaları siliniyor...")
            } else if let size = cachedModelSize {
                Text("Bu model yaklaşık \(size) yer kaplıyor. Silme işlemi geri alınamaz.")
            } else {
                Text("Seçilen model silinecektir. Bu işlem geri alınamaz.")
            }
        }
        .alert("Hata", isPresented: Binding(
            get: { deleteError != nil },
            set: { if !$0 { deleteError = nil } }
        )) {
            Button("Tamam") { deleteError = nil }
        } message: {
            Text(deleteError ?? "Bilinmeyen bir hata oluştu.")
        }
    }
    
    private func deleteModel(_ id: String) {
        isDeleting = true
        Task {
            do {
                try await manager.deleteModel(id)
                withAnimation(.easeOut(duration: 0.2)) {
                    isDeleting = false
                    modelToDelete = nil
                    cachedModelSize = nil
                }
            } catch {
                withAnimation {
                    deleteError = error.localizedDescription
                    isDeleting = false
                    modelToDelete = nil
                }
            }
        }
    }
    
    // MARK: - Components
    
    private var headerView: some View {
        VStack(spacing: 8) {
            Image(systemName: "cpu.fill")
                .font(.system(size: 40))
                .foregroundStyle(.linearGradient(colors: [.blue, .cyan], startPoint: .topLeading, endPoint: .bottomTrailing))
                .symbolEffect(.pulse)
            
            Text("Elite Titan Engine")
                .font(.system(size: 28, weight: .bold, design: .rounded))
            
            Text("Hybrid Intelligence Activation")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }
    
    private var welcomePhase: some View {
        VStack(spacing: 20) {
            Text("Powering your workspace with local Apple Silicon intelligence.")
                .multilineTextAlignment(.center)
                .font(.body)
            
            VStack(alignment: .leading, spacing: 12) {
                featureRow(icon: "lock.shield.fill", title: "100% Private", desc: "No data ever leaves your device.")
                featureRow(icon: "bolt.fill", title: "Metal Optimized", desc: "Native M-series GPU acceleration.")
                featureRow(icon: "wifi.slash", title: "Offline Ready", desc: "Works without an internet connection.")
            }
            .padding()
            .background(.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 16))
        }
    }
    
    private var instructionsPhase: some View {
        VStack(spacing: 24) {
            if manager.isDownloading {
                // DOWNLOAD PROGRESS VIEW
                VStack(spacing: 20) {
                    Text("Downloading \(manager.activeModelID.contains("3.5") ? "Titan v2" : "Titan v1")...")
                        .font(.headline)
                    
                    Text("Fetching \(manager.currentDownloadTask)...")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    
                    ProgressView(value: manager.downloadProgress)
                        .progressViewStyle(.linear)
                        .tint(.blue)
                        .frame(height: 8)
                        .background(Color.white.opacity(0.1), in: RoundedRectangle(cornerRadius: 4))
                    
                    Text("\(Int(manager.downloadProgress * 100))%")
                        .font(.system(.title3, design: .monospaced))
                        .fontWeight(.bold)
                }
                .padding(30)
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 24))
                .shadow(color: .blue.opacity(0.2), radius: 20)
            } else {
                // SELECTION & DOWNLOAD STATE
                VStack(spacing: 20) {
                    Text("Select Intelligence Profile")
                        .font(.headline)
                    
                    ScrollView {
                        VStack(spacing: 12) {
                            modelSelectionCard(
                                id: "Qwen2.5-7B-Instruct-4bit",
                                title: "Titan Balanced (v1)",
                                desc: "Qwen 2.5 7B. Fast, 8GB RAM optimized.",
                                badge: "4.5 GB"
                            )
                            
                            modelSelectionCard(
                                id: "Qwen3.5-9B-4bit",
                                title: "Titan Power (v2)",
                                desc: "Qwen 3.5 9B. Advanced reasoning, 16GB RAM req.",
                                badge: "6.2 GB",
                                isPremium: true
                            )
                            
                            if ProcessInfo.processInfo.physicalMemory < 16 * 1024 * 1024 * 1024 {
                                HStack {
                                    Image(systemName: "exclamationmark.triangle.fill")
                                    Text("Düşük RAM: Bu makinede 16GB altı bellek var. Titan v2 performansı düşük olabilir.")
                                }
                                .font(.caption2)
                                .foregroundColor(.orange)
                                .padding(8)
                                .background(Color.orange.opacity(0.1), in: RoundedRectangle(cornerRadius: 8))
                            }
                        }
                    }
                    .frame(maxHeight: 250)
                    
                    // v7.8.0 Quantization Selection
                    HStack {
                        Text("Denge:").font(.caption).foregroundStyle(.secondary)
                        Picker("", selection: $selectedQuant) {
                            Text("Q4_K (Hızlı)").tag("Q4_K_M")
                            Text("Q5_K (Önerilen)").tag("Q5_K_M")
                            Text("Q8_0 (Hassas)").tag("Q8_0")
                        }
                        .pickerStyle(.segmented)
                        .scaleEffect(0.9)
                    }
                    .padding(.horizontal)
                    
                    // v7.8.0 HF Token (Optional but Recommended)
                    HStack {
                        Image(systemName: "key.fill")
                            .font(.system(size: 10))
                        SecureField("HuggingFace Token (Opsiyonel)", text: $hfToken)
                            .textFieldStyle(.plain)
                            .font(.system(size: 11))
                    }
                    .padding(8)
                    .background(Color.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 8))
                    .padding(.horizontal)
                    
                    Button {
                        manager.startModelDownload()
                    } label: {
                        HStack {
                            Image(systemName: "arrow.down.circle.fill")
                            Text("Download Selected Model")
                        }
                        .padding(.horizontal, 24)
                        .padding(.vertical, 12)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .disabled(manager.activeModelID.isEmpty)
                }
            }
        }
        .padding()
    }
    
    private func modelSelectionCard(id: String, title: String, desc: String, badge: String, isPremium: Bool = false) -> some View {
        Button {
            manager.activeModelID = id
        } label: {
            HStack(spacing: 16) {
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(title).font(.system(size: 14, weight: .bold))
                        if isPremium {
                            Text("ADVANCED")
                                .font(.system(size: 8, weight: .black))
                                .padding(.horizontal, 4)
                                .padding(.vertical, 2)
                                .background(Color.blue, in: RoundedRectangle(cornerRadius: 4))
                                .foregroundStyle(.white)
                        }
                    }
                    Text(desc).font(.system(size: 12)).foregroundStyle(.secondary)
                }
                
                Spacer()
                
                Text(badge)
                    .font(.system(size: 10, design: .monospaced))
                    .padding(6)
                    .background(Color.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 8))
                
                if manager.isModelAvailable(id) {
                    Button(role: .destructive) {
                        modelToDelete = id
                        Task {
                            cachedModelSize = await manager.modelSize(for: id)
                        }
                    } label: {
                        Image(systemName: "trash")
                            .foregroundStyle(.red)
                            .padding(8)
                            .background(Color.red.opacity(0.1), in: Circle())
                    }
                    .disabled(isDeleting || id == manager.activeModelID)
                    .transition(.scale.combined(with: .opacity))
                }
                
                Image(systemName: manager.activeModelID == id ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(manager.activeModelID == id ? Color.blue : Color.secondary)
            }
            .padding()
            .background(manager.activeModelID == id ? Color.blue.opacity(0.1) : Color.white.opacity(0.02))
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .stroke(manager.activeModelID == id ? Color.blue : Color.white.opacity(0.1), lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 16))
        }
        .buttonStyle(.plain)
    }
    
    private var successPhase: some View {
        VStack(spacing: 20) {
            ZStack {
                Circle()
                    .fill(Color.green.opacity(0.15))
                    .frame(width: 120, height: 120)
                
                Image(systemName: "checkmark.seal.fill")
                    .font(.system(size: 60))
                    .foregroundStyle(.green)
                    .symbolEffect(.bounce, value: manager.isModelReady)
            }
            
            Text("Titan Engine Active")
                .font(.system(size: 24, weight: .bold))
            
            Text("Local intelligence is initialized and ready for hardware-accelerated inference.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
            
            HStack {
                Image(systemName: "cpu")
                Text(manager.modelPath?.lastPathComponent ?? "Default Model")
            }
            .font(.system(.caption, design: .monospaced))
            .padding(10)
            .background(.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 12))
        }
        .transition(.asymmetric(insertion: .push(from: .bottom), removal: .opacity))
    }
    
    private var footerView: some View {
        HStack {
            if manager.isModelReady {
                Button { dismiss() } label: {
                    Text("Enter Chat Arena")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .tint(.blue)
            } else if !manager.isDownloading {
                Button("Finish Later") { dismiss() }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                
                Spacer()
                
                if setupPhase == 0 {
                    Button("Get Started") {
                        withAnimation { setupPhase = 1 }
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                }
            }
        }
    }
    
    private func featureRow(icon: String, title: String, desc: String) -> some View {
        HStack(spacing: 16) {
            ZStack {
                Circle().fill(Color.blue.opacity(0.1)).frame(width: 32, height: 32)
                Image(systemName: icon).font(.system(size: 14)).foregroundStyle(.blue)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.system(size: 14, weight: .semibold))
                Text(desc).font(.system(size: 12)).foregroundStyle(.secondary)
            }
        }
    }
}
