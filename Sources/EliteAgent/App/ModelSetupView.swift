import SwiftUI
import EliteAgentCore

/// EliteAgent v9.0 Universal Model Hub.
/// Manages Local, Cloud, and Ollama models with a zero-config grid UI.
public struct ModelSetupView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var modelManager = ModelManager.shared
    @State private var toastMessage: String? = nil
    @State private var toastType: ToastType = .info
    
    enum ToastType { case info, error, success }
    
    // Grid Layout Configuration
    private let columns = [
        GridItem(.adaptive(minimum: 220, maximum: 260), spacing: 20)
    ]
    
    public init() {}
    
    public var body: some View {
        ZStack {
            // macOS Sequoia Adaptive Background
            Rectangle()
                .fill(.ultraThinMaterial)
                .ignoresSafeArea()
            
            VStack(spacing: 24) {
                headerSection
                
                ScrollView {
                    VStack(alignment: .leading, spacing: 32) {
                        // Section 1: LOCAL TITAN MODELS
                        modelSection(title: "LOCAL TITAN ENGINE", icon: "cpu.fill", filter: .local)
                        
                        // Section 2: CLOUD MODELS
                        modelSection(title: "CLOUD PROVIDERS", icon: "cloud.fill", filter: .cloud)
                        
                        diskUsageFooter
                    }
                    .padding(20)
                }
                
                footerSection
            }
            .padding(24)
            
            // Toast Overlay
            if let msg = toastMessage {
                VStack {
                    Spacer()
                    HStack {
                        Image(systemName: toastType == .error ? "exclamationmark.triangle.fill" : "checkmark.circle.fill")
                        Text(msg)
                    }
                    .font(.subheadline.bold())
                    .padding(.horizontal, 16).padding(.vertical, 10)
                    .background(toastType == .error ? Color.red : Color.blue)
                    .foregroundStyle(.white)
                    .clipShape(Capsule())
                    .shadow(radius: 4)
                    .padding(.bottom, 60)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                }
                .onAppear {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                         withAnimation { toastMessage = nil }
                    }
                }
            }
        }
        .frame(width: 720, height: 600)
    }
    
    // MARK: - Actions
    
    func showToast(_ message: String, type: ToastType = .info) {
        withAnimation {
            self.toastMessage = message
            self.toastType = type
        }
    }
    
    // MARK: - Sections
    
    private var headerSection: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Model Merkezi")
                    .font(.system(size: 28, weight: .bold))
                Text("Cihaz Analizi: \(AutoConfigManager.shared.recommendation.ramDescription) tespit edildi. Titan Engine yerel yürütme için optimize edildi.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            // Auto Config Badge
            HStack(spacing: 6) {
                Image(systemName: "bolt.shield.fill")
                Text("Auto-Config: \(AutoConfigManager.shared.autoTune().preset.rawValue.uppercased())")
            }
            .font(.caption2.bold())
            .padding(.horizontal, 8).padding(.vertical, 4)
            .background(.blue.opacity(0.1), in: Capsule())
            .foregroundStyle(.blue)
            
            // v9.6: Stress Simulation Button
            Button {
                Task { await LocalModelWatchdog.shared.simulateStress() }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "flame.fill")
                    Text("Stres Testi")
                }
                .font(.caption2.bold())
                .padding(.horizontal, 8).padding(.vertical, 4)
                .background(.red.opacity(0.1), in: Capsule())
                .foregroundStyle(.red)
            }
            .buttonStyle(.plain)
            .help("Düşük VRAM ve termal baskı simüle ederek kurtarma sistemini test et")
        }
    }
    
    private func modelSection(title: String, icon: String, filter: ProviderCategory) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            Label(title, systemImage: icon)
                .font(.caption.bold())
                .foregroundStyle(.secondary)
            
            LazyVGrid(columns: columns, spacing: 20) {
                ForEach(ModelRegistry.availableModels.filter { match($0.provider, category: filter) }) { model in
                    ModelCard(model: model, showToast: showToast)
                }
            }
        }
    }
    
    private var diskUsageFooter: some View {
        VStack(alignment: .leading, spacing: 8) {
            Divider()
            HStack {
                Image(systemName: "internaldrive.fill")
                Text("Disk Kullanımı: 4.2 GB used / 16 GB available") // Hardcoded placeholder for Phase 1
                Spacer()
                Text("Cihaz: M4 Air (8-core)") // Auto-detect placeholder
            }
            .font(.caption2)
            .foregroundStyle(.secondary)
        }
        .padding(.top, 20)
    }
    
    private var footerSection: some View {
        HStack {
            Button("Kapat") { dismiss() }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
            
            Spacer()
            
            Button("Sohbete Dön") { dismiss() }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
        }
    }
    
    // MARK: - Helper Methods
    
    private enum ProviderCategory { case local, cloud }
    
    private func match(_ provider: ModelProvider, category: ProviderCategory) -> Bool {
        switch (provider, category) {
        case (.localTitanEngine, .local): return true
        case (.cloudOpenRouter, .cloud): return true
        default: return false
        }
    }
}

// MARK: - Subviews

struct ModelCard: View {
    let model: ModelCatalog
    let showToast: (String, ModelSetupView.ToastType) -> Void
    @StateObject private var manager = ModelManager.shared
    @State private var errorMessage: String?
    @State private var isLoading = false
    
    private var isDownloaded: Bool { manager.installedModelIDs.contains(model.id) }
    private var isActive: Bool { AISessionState.shared.selectedModel == model.id }
    private var isCurrentlyLoading: Bool { ModelManager.shared.loadingModelID == model.id }
    private var progress: Double? { manager.downloadProgress[model.id] }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(model.name)
                    .font(.headline)
                    .lineLimit(1)
                Spacer()
                if manager.verifyIntegrity(id: model.id) {
                    Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                } else if manager.doesModelDirectoryExist(id: model.id) {
                    Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.red)
                }
            }
            
            VStack(alignment: .leading, spacing: 4) {
                Text("\(model.size) • \(model.quantization)")
                Text(model.estimatedSpeed)
            }
            .font(.caption2)
            .foregroundStyle(.secondary)
            
            Spacer()
            
            // v10.7: Unified Integrity Logic
            let isActuallyInstalled = manager.verifyIntegrity(id: model.id)
            let directoryExists = manager.doesModelDirectoryExist(id: model.id)
            
            if isActuallyInstalled {
                if isActive {
                    Label("🟢 Aktif", systemImage: "checkmark.circle.fill")
                        .font(.caption2.bold())
                        .foregroundStyle(.green)
                } else {
                    actionButton
                }
            } else if let p = progress, p < 1.0 {
                VStack(spacing: 4) {
                    ProgressView(value: p)
                        .progressViewStyle(.linear)
                        .tint(.blue)
                    Text("%\(Int(p * 100)) • \(manager.downloadStatus[model.id] ?? "Başlatılıyor...")")
                        .font(.system(size: 9).monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            } else if directoryExists {
                // INCOMPLETE or CORRUPTED
                HStack {
                    Label("⚠️ Eksik", systemImage: "exclamationmark.triangle.fill")
                        .font(.caption2.bold())
                        .foregroundStyle(.red)
                    Spacer()
                    repairButton
                }
            } else {
                actionButton
            }
        }
        .padding(16)
        .frame(height: 140)
        .background(.primary.opacity(0.03), in: RoundedRectangle(cornerRadius: 16))
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(.primary.opacity(0.1), lineWidth: 1)
        )
        .alert("Model Hatası", isPresented: .init(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
            Button("Tamam", role: .cancel) {}
        } message: {
            if let msg = errorMessage { Text(msg) }
        }
    }
    
    @ViewBuilder
    private var repairButton: some View {
        HStack {
            Button {
                isLoading = true
                Task {
                    do {
                        try await manager.repairModel(model.id)
                        isLoading = false
                    } catch {
                        errorMessage = "Onarım başarısız: \(error.localizedDescription)"
                        isLoading = false
                    }
                }
            } label: {
                if isLoading {
                    ProgressView().controlSize(.small)
                } else {
                    Text("🔧 Onar")
                }
            }
            .buttonStyle(.bordered)
            .foregroundStyle(.orange)
            
            Button("Sil") {
                Task {
                    do {
                        try await ModelSetupManager.shared.deleteModel(model.id)
                        showToast("🗑️ \(model.name) silindi.", .info)
                    } catch {
                        errorMessage = error.localizedDescription
                    }
                }
            }
            .buttonStyle(.plain)
            .foregroundStyle(.red)
            .font(.caption2)
        }
    }

    @ViewBuilder
    private var actionButton: some View {
        if manager.verifyIntegrity(id: model.id) {
            HStack {
                Button {
                    Task {
                        do {
                            try await manager.switchTo(model.id)
                            showToast("✅ \(model.name) yüklendi! Hazır.", .success)
                        } catch {
                            showToast("Yükleme Başarısız: \(error.localizedDescription)", .error)
                        }
                    }
                } label: {
                    if isCurrentlyLoading {
                        ProgressView().controlSize(.small).scaleEffect(0.8)
                    } else {
                        Text("Yükle")
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(isCurrentlyLoading)
                
                Button("Sil") {
                    Task {
                        do {
                            try await ModelSetupManager.shared.deleteModel(model.id)
                            showToast("🗑️ \(model.name) silindi.", .info)
                        } catch {
                            errorMessage = error.localizedDescription
                        }
                    }
                }
                .buttonStyle(.plain)
                .foregroundStyle(.red)
                .font(.caption2)
                .disabled(isCurrentlyLoading)
            }
        } else if case .cloudOpenRouter = model.provider {

            Button("Bağlan") {
                isLoading = true
                Task { 
                    do {
                        try await manager.switchTo(model.id) 
                        isLoading = false
                    } catch {
                        errorMessage = error.localizedDescription
                        isLoading = false
                    }
                }
            }
            .buttonStyle(.borderedProminent)
            .disabled(isLoading)
        } else {
            // Check if repair is needed (weights exist but metadata might be missing)
            let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            let modelDir = appSupport.appendingPathComponent("EliteAgent/Models").appendingPathComponent(model.id)
            let weightsExist = FileManager.default.fileExists(atPath: modelDir.appendingPathComponent("model.safetensors").path) || 
                               FileManager.default.fileExists(atPath: modelDir.appendingPathComponent("weights.npz").path)
            
            if weightsExist && !isDownloaded {
                Button {
                    isLoading = true
                    Task {
                        do {
                            try await manager.repairModel(model.id)
                            isLoading = false
                        } catch {
                            errorMessage = "Onarım başarısız: \(error.localizedDescription)"
                            isLoading = false
                        }
                    }
                } label: {
                    if isLoading {
                        ProgressView().controlSize(.small)
                    } else {
                        Text("🔧 Tamamla")
                    }
                }
                .buttonStyle(.bordered)
                .foregroundStyle(.orange)
                .help("Eksik metadata dosyalarını indir")
                .disabled(isLoading)
            } else {
                Button("İndir") {
                    isLoading = true
                    Task { 
                        do {
                            try await manager.download(model) 
                            isLoading = false
                        } catch {
                            errorMessage = error.localizedDescription
                            isLoading = false
                        }
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(isLoading)
            }
        }
    }
}
