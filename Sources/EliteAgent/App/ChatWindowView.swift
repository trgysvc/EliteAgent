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
                                
                                if !orchestrator.steps.isEmpty && orchestrator.status != .idle {
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
                    
                    inputArea
                }
                
                if ModelManager.shared.loadedModels.isEmpty && !VaultManager.shared.hasCloudProvider() {
                    emptyStateOverlay
                }
            }
            .sheet(isPresented: $showingOnboarding) {
                OnboardingWizardView()
            }
            .overlay {
                SelfHealingOverlay()
            }
            .sheet(isPresented: $showingSettings) {
                SettingsView(orchestrator: orchestrator, modelPickerVM: modelPickerVM)
            }
            .sheet(isPresented: $showingTitanAssistant) {
                ModelSetupView()
            }
            .fileImporter(
                isPresented: $showingFileImporter,
                allowedContentTypes: [.pdf, .plainText, .swiftSource, .json],
                allowsMultipleSelection: false
            ) { result in
                if case .success(let urls) = result, let url = urls.first {
                    processVM.startUpload(fileURL: url, actor: InferenceActor.shared)
                }
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
            .disabled(promptText.isEmpty || orchestrator.status == .working)
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
            
            if modelPickerVM.hasOllama {
                Section("LOCAL - OLLAMA") {
                    ForEach(modelPickerVM.filteredOllamaModels) { model in
                        Button { modelPickerVM.selectModel(model) } label: {
                            Label(model.name, systemImage: model.icon)
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

struct ChatBubble: View {
    let message: ChatMessage
    @State private var parseError: Bool = false
    
    var body: some View {
        HStack {
            if message.role == .user { Spacer() }
            
            VStack(alignment: message.role == .user ? .trailing : .leading, spacing: 8) {
                if message.isStatus {
                    StatusAnimationBubble(content: message.content)
                } else if let report = tryParseReport(message.content) {
                    ResearchReportView(report: report).frame(maxWidth: 600)
                } else {
                    Text(message.content)
                        .font(.subheadline)
                        .padding(12)
                        .background(message.role == .user ? Color.accentColor : Color.secondary.opacity(0.1))
                        .foregroundStyle(message.role == .user ? .white : .primary)
                        .cornerRadius(14)
                }
            }
            
            if message.role == .assistant { Spacer() }
        }
    }
    
    private func tryParseReport(_ content: String) -> ResearchReport? {
        guard UserDefaults.standard.bool(forKey: "enableResearchMode") else { return nil }
        let jsonStr = ThinkParser.extractJSONRobustly(content)
        guard jsonStr.contains("\"report\""), let data = jsonStr.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode(ResearchReport.self, from: data)
    }
}

struct StatusAnimationBubble: View {
    let content: String
    @State private var isAnimating = false
    
    var body: some View {
        HStack(spacing: 8) {
            Text(content)
                .font(.subheadline.italic())
            
            HStack(spacing: 4) {
                Circle().frame(width: 5, height: 5).scaleEffect(isAnimating ? 1 : 0.5).opacity(isAnimating ? 1 : 0.3)
                    .animation(.easeInOut(duration: 0.6).repeatForever().delay(0), value: isAnimating)
                Circle().frame(width: 5, height: 5).scaleEffect(isAnimating ? 1 : 0.5).opacity(isAnimating ? 1 : 0.3)
                    .animation(.easeInOut(duration: 0.6).repeatForever().delay(0.2), value: isAnimating)
                Circle().frame(width: 5, height: 5).scaleEffect(isAnimating ? 1 : 0.5).opacity(isAnimating ? 1 : 0.3)
                    .animation(.easeInOut(duration: 0.6).repeatForever().delay(0.4), value: isAnimating)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(Color.secondary.opacity(0.15))
        .foregroundStyle(Color.secondary)
        .cornerRadius(16)
        .onAppear {
            isAnimating = true
        }
    }
}

struct WorkflowView: View {
    @ObservedObject var orchestrator: Orchestrator
    var body: some View {
        DisclosureGroup {
            VStack(alignment: .leading, spacing: 8) {
                ForEach(orchestrator.steps) { step in
                    HStack {
                        StepIcon(status: step.status)
                        Text(step.name).font(.subheadline)
                        Spacer()
                        Text(step.latency).font(.caption2).foregroundStyle(.secondary)
                    }
                }
            }.padding()
        } label: {
            Label("İş Adımları", systemImage: "cpu.fill").font(.caption.bold())
        }
    }
}

struct HealthStatusBadge: View {
    @StateObject private var watchdog = LocalModelWatchdog.shared
    
    var body: some View {
        Text(watchdog.status.rawValue)
            .font(.caption2.bold())
            .padding(.horizontal, 6)
            .background(statusColor.opacity(0.1))
            .foregroundStyle(statusColor)
    }
    
    private var statusColor: Color {
        switch watchdog.status {
        case .healthy: return .green
        case .degraded: return .orange
        case .critical: return .red
        case .offline: return .red
        }
    }
}

struct StatusIndicator: View {
    let status: AgentStatus
    let isModelSelected: Bool
    let hasMessages: Bool
    @StateObject private var watchdog = LocalModelWatchdog.shared
    
    var body: some View { 
        Circle()
            .fill(watchdog.status == .healthy ? .green : .red)
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
