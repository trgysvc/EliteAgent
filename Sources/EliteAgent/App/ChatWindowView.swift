import SwiftUI
import Combine
import EliteAgentCore

public struct GlassEffectStyle: Sendable {
    public static let regular = GlassEffectStyle()
    public func interactive() -> GlassEffectStyle { return self }
}

public extension View {
    func glassEffect(_ style: GlassEffectStyle) -> some View {
        self.background(Material.regularMaterial)
    }
}

public struct ChatWindowView: View {
    @ObservedObject public var orchestrator: Orchestrator
    @ObservedObject public var modelPickerVM: ModelPickerViewModel
    @State private var promptText: String = ""
    @StateObject private var modelSetup = ModelSetupManager.shared
    @State private var showingTitanAssistant: Bool = false
    @State private var showingSettings: Bool = false
    
    @StateObject private var processVM = ChatProcessViewModel()
    @State private var sessionState = AISessionState.shared
    
    @State private var attachedFileURL: URL? = nil
    @State private var showingFileImporter = false
    @State private var isScanningDocument = false
    @State private var isDraggingOver = false 
    @State private var showingOnboarding = false
    @State private var autoFallbackMessage: String? = nil
    
    public init(orchestrator: Orchestrator, modelPickerVM: ModelPickerViewModel) {
        self.orchestrator = orchestrator
        self.modelPickerVM = modelPickerVM
    }
    
    public var body: some View {
        NavigationSplitView {
            List(orchestrator.pastSessions, selection: $orchestrator.selectedSessionID) { session in
                VStack(alignment: .leading, spacing: 4) {
                    Text(session.title)
                        .font(.body)
                        .foregroundStyle(orchestrator.selectedSessionID == session.id ? Color.primary : Color.primary.opacity(0.8))
                        .lineLimit(1)
                    
                    HStack {
                        Text(session.createdAt.formatted(.relative(presentation: .named)))
                        Spacer()
                        if session.metadata.cost > 0 {
                            Text("$\(String(format: "%.3f", NSDecimalNumber(decimal: session.metadata.cost).doubleValue))")
                        }
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
                .padding(.vertical, 4)
                .tag(session.id)
            }
            .listStyle(.sidebar)
            .navigationTitle("Conversations")
            .onChange(of: orchestrator.selectedSessionID) { _, newValue in
                if let id = newValue, let session = orchestrator.pastSessions.first(where: { $0.id == id }) {
                    orchestrator.selectSession(session)
                }
            }
            .safeAreaInset(edge: .bottom) {
                VStack(spacing: 0) {
                    Divider()
                    FooterButton(action: { orchestrator.startNewConversation() })
                }
                .background(.ultraThinMaterial)
            }
        } detail: {
            ZStack {
                VisualizerView()
                    .ignoresSafeArea()
                    .opacity(orchestrator.status == .working ? 0.2 : 0.05)
                
                VStack(spacing: 0) {
                    chatHeader
                    
                    ScrollViewReader { proxy in
                        ScrollView {
                            VStack(spacing: 24) {
                                ForEach(orchestrator.currentMessages) { message in
                                    ChatBubble(message: message)
                                        .id(message.id)
                                }
                                
                                if orchestrator.status == .working && !orchestrator.steps.isEmpty {
                                    WorkflowView(orchestrator: orchestrator)
                                        .padding(.horizontal)
                                }
                            }
                            .padding(.vertical, 20)
                            .padding(.horizontal, 16)
                        }
                        .onChange(of: orchestrator.currentMessages.count) {
                            if let last = orchestrator.currentMessages.last {
                                withAnimation { proxy.scrollTo(last.id, anchor: .bottom) }
                            }
                        }
                    }
                    .overlay {
                        if isDraggingOver {
                            FileUploadZone { url in
                                processVM.startUpload(fileURL: url, actor: InferenceActor.shared)
                            }
                            .background(.ultraThinMaterial.opacity(0.8))
                        }
                    }
                    .overlay {
                        processOverlay(viewModel: processVM)
                    }
                    .overlay {
                        if sessionState.requiresUserAcknowledgement {
                            fallbackApprovalModal
                        }
                    }
                    .overlay {
                        if sessionState.requiresPermissionAcknowledgement {
                            permissionApprovalModal
                        }
                    }
                    .overlay {
                        if sessionState.isRestartingEngine {
                            ZStack {
                                Color.black.opacity(0.4).ignoresSafeArea()
                                VStack(spacing: 20) {
                                    ProgressView().controlSize(.large)
                                    VStack(spacing: 8) {
                                        Text("Titan Motoru Optimize Ediliyor...").font(.headline)
                                        Text("VRAM temizleniyor ve model yeniden yükleniyor.").font(.subheadline).foregroundStyle(.secondary)
                                    }
                                }
                                .padding(30)
                                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 24))
                            }
                        }
                    }
                    
                    if let statusMsg = orchestrator.overlayMessage {
                        StatusOverlayView(
                            message: statusMsg, 
                            onCancel: orchestrator.status == .working ? { orchestrator.cancelCurrentTask() } : nil
                        )
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                        .padding(.bottom, 8)
                    }
                    
                    inputArea
                }
                
                if ModelManager.shared.installedModelIDs.isEmpty && !VaultManager.shared.hasCloudProvider() {
                    emptyStateOverlay
                }
            }
            .sheet(isPresented: $showingOnboarding) {
                OnboardingWizardView()
            }
            .overlay(content: { SelfHealingOverlay() })
            .sheet(isPresented: $showingSettings) {
                SettingsView(orchestrator: orchestrator, modelPickerVM: modelPickerVM)
            }
            .sheet(isPresented: $showingTitanAssistant) {
                ModelSetupView()
            }
            .onAppear {
                processVM.onCompletion = { url in
                    Task {
                        try? await orchestrator.submitTask(prompt: "Aşağıdaki dosyayı analiz et: \(url.lastPathComponent)\nDosya Yolu: \(url.path)")
                    }
                }
            }
            .fileImporter(
                isPresented: $showingFileImporter,
                allowedContentTypes: [.item, .data, .content, .pdf, .plainText, .swiftSource, .json, .text],
                allowsMultipleSelection: false
            ) { result in
                if case .success(let urls) = result, let url = urls.first {
                    processVM.startUpload(fileURL: url, actor: InferenceActor.shared)
                }
            }
            .onDrop(of: [.fileURL], isTargeted: $isDraggingOver) { providers in
                guard let provider = providers.first else { return false }
                _ = provider.loadObject(ofClass: URL.self) { url, error in
                    if let url = url {
                        Task { @MainActor in
                            processVM.startUpload(fileURL: url, actor: InferenceActor.shared)
                        }
                    }
                }
                return true
            }
        }
    }
    
    private var chatHeader: some View {
        HStack(spacing: 12) {
            ModelPickerMenu(modelPickerVM: modelPickerVM)
            
            if sessionState.isFallbackActive {
                Label("Bulut", systemImage: "cloud.fill")
                    .font(.caption2.bold())
                    .padding(.horizontal, 8)
                    .padding(.vertical, 2)
                    .background(.orange, in: Capsule())
                    .foregroundStyle(.white)
            }
            
            Spacer()
            
            if isScanningDocument {
                ProgressView().controlSize(.small)
            } else {
                StatusIndicator(
                    status: orchestrator.status, 
                    isModelSelected: modelPickerVM.selected != nil,
                    hasMessages: !orchestrator.currentMessages.isEmpty
                )
                HealthStatusBadge()
            }
            
            Spacer()
            
            SessionStatsView(orchestrator: orchestrator, showingSettings: $showingSettings)
            
            Button {
                NSApplication.shared.terminate(nil)
            } label: {
                Image(systemName: "power")
                    .foregroundStyle(.red)
            }
            .buttonStyle(.plain)
            .help("EliteAgent'ı Kapat")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(.ultraThinMaterial)
        .overlay(Divider(), alignment: .bottom)
    }
    
    private var inputArea: some View {
        HStack(spacing: 12) {
            Button { showingFileImporter = true } label: {
                Image(systemName: "plus").font(.headline).foregroundStyle(Color.accentColor)
            }
            .buttonStyle(.plain)
            .frame(width: 32, height: 32)
            .background(Color.accentColor.opacity(0.1), in: Circle())
            
            TextField("EliteAgent'a Sor...", text: $promptText)
                .textFieldStyle(.plain)
                .padding(12)
                .background(.secondary.opacity(0.05), in: RoundedRectangle(cornerRadius: 12))
                .onSubmit(submitTask)
            
            Button(action: submitTask) {
                Image(systemName: "arrow.up.circle.fill").font(.title).foregroundStyle(Color.accentColor)
            }
            .buttonStyle(.plain)
            .disabled(promptText.isEmpty)
            
            if orchestrator.queuedTasksCount > 0 {
                Text("\(orchestrator.queuedTasksCount)")
                    .font(.caption2.bold())
                    .padding(4)
                    .background(.orange, in: Circle())
                    .foregroundStyle(.white)
            }
        }
        .padding(16)
    }
    
    private func submitTask() {
        guard !promptText.isEmpty else { return }
        let text = promptText
        promptText = ""
        Task {
            try? await orchestrator.submitTask(prompt: text)
        }
    }
    
    private var emptyStateOverlay: some View {
        ZStack {
            Color.black.opacity(0.4).ignoresSafeArea()
            VStack(spacing: 32) {
                VStack(spacing: 12) {
                    Image(systemName: "sparkles").font(.system(size: 64)).foregroundStyle(Color.accentColor)
                    Text("EliteAgent Kurulumu").font(.title.bold())
                    Text("Sohbet etmeye başlamak için bir model yükleyin.").font(.subheadline).foregroundStyle(.secondary)
                }
                Button("Kurulum Sihirbazını Başlat") { showingOnboarding = true }
                    .buttonStyle(.borderedProminent).controlSize(.large)
            }
            .padding(40)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 32))
        }
    }
    
    private var fallbackApprovalModal: some View {
        VStack { Text("Fallback Modal Placeholder") }
    }
    
    private var permissionApprovalModal: some View {
        VStack { Text("Permission Modal Placeholder") }
    }
}

// MARK: - Subviews

struct ModelPickerMenu: View {
    @ObservedObject var modelPickerVM: ModelPickerViewModel
    
    var body: some View {
        Menu {
            if !modelPickerVM.installedLocalModels.isEmpty {
                Section("LOCAL - TITAN ENGINE") {
                    ForEach(modelPickerVM.installedLocalModels) { catalog in
                        Button {
                            let source = ModelSource.localMLX(id: catalog.id, name: catalog.name, ramGB: 16, hasThink: catalog.id.contains("think"))
                            modelPickerVM.selectModel(source)
                        } label: {
                            HStack {
                                Image(systemName: "cpu.fill")
                                Text(catalog.name)
                                Spacer()
                                Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                            }
                        }
                    }
                }
            }
            
            Section(modelPickerVM.hasOpenRouter ? "CLOUD - OPENROUTER" : "CLOUD") {
                ForEach(modelPickerVM.filteredCloudModels) { model in
                    Button { modelPickerVM.selectModel(model) } label: {
                        Label(model.name, systemImage: model.icon)
                    }
                }
            }
            
            Divider()
            Button("Kurulum Sihirbazı...") { NotificationCenter.default.post(name: NSNotification.Name("OpenModelSetup"), object: nil) }
        } label: {
            HStack(spacing: 8) {
                Text(modelPickerVM.selected?.name ?? "Model Seç").font(.subheadline.bold())
                Image(systemName: "chevron.up.chevron.down").font(.caption2)
            }
            .foregroundStyle(.primary)
        }
        .menuStyle(.button)
        .disabled(modelPickerVM.isLoading)
    }
}




struct WorkflowView: View {
    @ObservedObject var orchestrator: Orchestrator
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack(spacing: 12) {
                if orchestrator.status == .working {
                    Image("AppIcon") // Assuming AppIcon is available or using a generic elite icon
                        .resizable()
                        .frame(width: 24, height: 24)
                        .clipShape(Circle())
                } else {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                        .font(.title3)
                }
                
                Text(orchestrator.status == .working ? "Working" : "Task completed.")
                    .font(.subheadline.bold())
                    .foregroundStyle(.primary)
            }
            .padding(.bottom, 4)
            
            // Active Step (Second Line)
            if let step = orchestrator.steps.last {
                Text(step.name)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
        }
        .padding(12)
        .background(Color.secondary.opacity(0.1))
        .cornerRadius(14)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct StepIconDesign: View {
    let status: String
    let actionName: String
    
    var body: some View {
        Group {
            if status == "Executing" {
                ProgressView().controlSize(.small)
            } else if status == "failed" || status == "error" || status == "warning" {
                Image(systemName: "xmark.circle").foregroundStyle(.red)
            } else {
                let lower = actionName.lowercased()
                let iconName: String = {
                    if lower.contains("shell") || lower.contains("terminal") { return "terminal" }
                    if lower.contains("read") || lower.contains("check") || lower.contains("audit") { return "doc.text" }
                    if lower.contains("search") { return "magnifyingglass" }
                    if lower.contains("write") || lower.contains("save") { return "square.and.pencil" }
                    return "checkmark.circle"
                }()
                
                Image(systemName: iconName)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

struct HealthStatusBadge: View {
    @StateObject private var watchdog = LocalModelWatchdog.shared
    
    var body: some View {
        let text: String = {
            if watchdog.status == .offline { return "Offline" }
            return watchdog.isBusy ? "Çalışıyor" : "Hazır"
        }()
        
        Text(text)
            .font(.caption2.bold())
            .padding(.horizontal, 6)
            .background(statusColor.opacity(0.1))
            .foregroundStyle(statusColor)
    }
    
    private var statusColor: Color {
        if watchdog.status == .offline { return .red }
        return watchdog.isBusy ? .orange : .green
    }
}

struct StatusIndicator: View {
    let status: AgentStatus
    let isModelSelected: Bool
    let hasMessages: Bool
    @StateObject private var watchdog = LocalModelWatchdog.shared
    
    var body: some View { 
        let color: Color = {
            if watchdog.status == .offline { return .red }
            return watchdog.isBusy ? .orange : .green
        }()
        Circle()
            .fill(color)
            .frame(width: 8, height: 8) 
    }
}

struct SessionStatsView: View {
    @ObservedObject var orchestrator: Orchestrator
    @Binding var showingSettings: Bool
    var body: some View {
        HStack {
            Text("$\(String(format: "%.4f", NSDecimalNumber(decimal: orchestrator.costToday).doubleValue))").font(.footnote)
            Button { showingSettings.toggle() } label: { Image(systemName: "gearshape") }.buttonStyle(.plain)
        }
    }
}

struct FooterButton: View {
    let action: () -> Void
    var body: some View { Button(action: action) { Label("Yeni Sohbet", systemImage: "square.and.pencil") }.buttonStyle(.plain).padding() }
}

struct StepIcon: View {
    let status: String
    var body: some View { Image(systemName: status == "done" ? "checkmark.circle.fill" : "circle").foregroundColor(status == "done" ? .green : .secondary) }
}
struct StatusOverlayView: View {
    let message: String
    var onCancel: (() -> Void)? = nil
    @State private var rotation: Double = 0
    
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "gearshape.fill")
                .rotationEffect(.degrees(rotation))
                .onAppear {
                    withAnimation(.linear(duration: 2).repeatForever(autoreverses: false)) {
                        rotation = 360
                    }
                }
                .foregroundStyle(Color.accentColor)
            
            Text(message)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.primary)
            
            if let onCancel = onCancel {
                Button(action: onCancel) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(.ultraThinMaterial, in: Capsule())
        .overlay(
            Capsule()
                .stroke(Color.accentColor.opacity(0.2), lineWidth: 0.5)
        )
        .shadow(color: .black.opacity(0.1), radius: 10, y: 5)
        .padding(.horizontal)
    }
}
