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
    
    // Process Visualization logic carried over correctly
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
            // SIDEBAR: Clean Native macOS List
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
                // BACKGROUND: Visual density reduced for performance
                VisualizerView()
                    .ignoresSafeArea()
                    .opacity(orchestrator.status == .working ? 0.2 : 0.05)
                
                VStack(spacing: 0) {
                    // TOP BAR: Native header feel
                    chatHeader
                    
                    // CHAT CONTENT
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
                                        .transition(.opacity.combined(with: .move(edge: .bottom)))
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
                        // v7.7.0 Process Visualization Overlay
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
                                Color.black.opacity(0.4)
                                    .ignoresSafeArea()
                                
                                VStack(spacing: 20) {
                                    ProgressView()
                                        .controlSize(.large)
                                    
                                    VStack(spacing: 8) {
                                        Text("Titan Motoru Optimize Ediliyor...")
                                            .font(.headline)
                                        Text("VRAM temizleniyor ve model yeniden yükleniyor.")
                                            .font(.subheadline)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                                .padding(30)
                                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 24))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 24)
                                        .stroke(.white.opacity(0.1), lineWidth: 1)
                                )
                                .shadow(radius: 20)
                            }
                            .transition(.opacity.combined(with: .scale(scale: 0.95)))
                        }
                    }
                    
                    // INPUT BAR
                    inputArea
                }
                
                // v9.0.8: First-Run Hints Overlay
                VStack {
                    HStack {
                        Spacer()
                        FirstChatHintsView()
                    }
                    Spacer()
                }
                .allowsHitTesting(true)
                
                // v9.0.8: Empty State / Onboarding CTA
                if ModelManager.shared.loadedModels.isEmpty && !VaultManager.shared.hasCloudProvider() {
                    emptyStateOverlay
                }
            }
            .sheet(isPresented: $showingOnboarding) {
                OnboardingWizardView()
            }
            .overlay(alignment: .bottom) {
                if let msg = autoFallbackMessage {
                    HStack(spacing: 12) {
                        Label(msg, systemImage: "cloud.rainbow.half")
                            .font(.subheadline.bold())
                        
                        Button {
                            AISessionState.shared.isFallbackActive = false
                            withAnimation { autoFallbackMessage = nil }
                        } label: {
                            Text("↩️ Geri Al")
                                .font(.caption.bold())
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(.white.opacity(0.2), in: Capsule())
                        }
                        .buttonStyle(.plain)
                    }
                    .padding()
                    .background(.orange, in: RoundedRectangle(cornerRadius: 16))
                    .foregroundStyle(.white)
                    .padding(.bottom, 100)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .onAppear {
                        Task {
                            try? await Task.sleep(nanoseconds: 10 * 1_000_000_000)
                            withAnimation { autoFallbackMessage = nil }
                        }
                    }
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("app.eliteagent.autoFallbackTriggered"))) { note in
                if let msg = note.userInfo?["message"] as? String {
                    withAnimation { self.autoFallbackMessage = msg }
                }
            }
            .onAppear {
                let skipped = UserDefaults.standard.bool(forKey: "hasSkippedOnboarding")
                let noModels = ModelManager.shared.loadedModels.isEmpty && !VaultManager.shared.hasCloudProvider()
                
                if noModels && !skipped {
                    showingOnboarding = true
                }
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
                
                // v9.6: Integrity System Badge
                HealthStatusBadge()
            }
            
            Spacer()
            
            SessionStatsView(orchestrator: orchestrator, showingSettings: $showingSettings)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(.ultraThinMaterial)
        .overlay(Divider(), alignment: .bottom)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Chat Header")
    }
    
    private var inputArea: some View {
        VStack(spacing: 8) {
            if let file = attachedFileURL {
                fileChip(file: file)
            }
            
            HStack(spacing: 12) {
                Button { showingFileImporter = true } label: {
                    Image(systemName: "plus")
                        .font(.headline)
                        .foregroundStyle(Color.accentColor)
                }
                .buttonStyle(.plain)
                .frame(width: 32, height: 32)
                .background(Color.accentColor.opacity(0.1), in: Circle())
                .accessibilityLabel("Dosya Ekle")
                .accessibilityHint("Yeni bir dosya yüklemek için Finder'ı açar")
                .help("Dosya ekle")
                
                TextField("EliteAgent'a Sor...", text: $promptText)
                    .textFieldStyle(.plain)
                    .padding(12)
                    .background(.secondary.opacity(0.05), in: RoundedRectangle(cornerRadius: 12))
                    .submitLabel(.send)
                    .onSubmit(submitTask)
                    .disabled(sessionState.isRestartingEngine)
                
                Button(action: submitTask) {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.title)
                        .symbolRenderingMode(.hierarchical)
                        .foregroundStyle(Color.accentColor)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Gönder")
                .accessibilityHint("Giriş yapılan metni veya dosyayı işleme koyar")
                .disabled((promptText.isEmpty && attachedFileURL == nil) || orchestrator.status == .working || sessionState.isRestartingEngine)
                .keyboardShortcut(.return, modifiers: .command)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .background(.thickMaterial, in: RoundedRectangle(cornerRadius: 22))
            .shadow(color: .black.opacity(0.03), radius: 3, y: 1)
        }
        .padding(16)
    }
    
    private func fileChip(file: URL) -> some View {
        HStack {
            Image(systemName: "doc.fill")
                .foregroundStyle(Color.accentColor)
            Text(file.lastPathComponent)
                .font(.caption.bold())
            Button {
                withAnimation { attachedFileURL = nil }
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(Color.accentColor.opacity(0.1), in: Capsule())
    }
    
    private func submitTask() {
        guard !promptText.isEmpty || attachedFileURL != nil else { return }
        let text = promptText
        promptText = ""
        withAnimation { attachedFileURL = nil }
        
        Task {
            try? await orchestrator.submitTask(prompt: text)
        }
    }
    
    // v9.0.8: Premium Setup CTA
    private var emptyStateOverlay: some View {
        ZStack {
            Color.black.opacity(0.4).ignoresSafeArea()
            VStack(spacing: 32) {
                VStack(spacing: 12) {
                    Image(systemName: "sparkles")
                        .font(.system(size: 64))
                        .foregroundStyle(
                            LinearGradient(colors: [.accentColor, .purple], startPoint: .topLeading, endPoint: .bottomTrailing)
                        )
                    
                    Text("EliteAgent Kurulumu")
                        .font(.title.bold())
                    
                    Text("Sohbet etmeye başlamak için yerel bir model yükleyin veya bir bulut sağlayıcısı tanımlayın.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 40)
                }
                
                VStack(spacing: 16) {
                    Button {
                        showingOnboarding = true
                    } label: {
                        Label("Kurulum Sihirbazını Başlat", systemImage: "wand.and.stars")
                            .font(.headline)
                            .frame(maxWidth: 280)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    
                    Button("Kılavuzu Görüntüle") {
                        if let url = URL(string: "https://eliteagent.ai/docs") {
                            NSWorkspace.shared.open(url)
                        }
                    }
                    .buttonStyle(.link)
                }
            }
            .padding(40)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 32))
            .overlay(RoundedRectangle(cornerRadius: 32).stroke(.white.opacity(0.1), lineWidth: 1))
            .shadow(color: .black.opacity(0.3), radius: 30)
        }
    }
    
    // processOverlay logic is handled in ChatView+ProcessIntegration.swift
    
    private var fallbackApprovalModal: some View {
        ZStack {
            Color.black.opacity(0.3).ignoresSafeArea()
            VStack(spacing: 24) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.title).foregroundStyle(.orange)
                Text("Yerel Model Hazır Değil").font(.headline)
                Text("Bulut modeli ile devam etmek istiyor musunuz?").font(.subheadline).multilineTextAlignment(.center)
                VStack(spacing: 12) {
                    Button("Bulut ile Devam Et") { orchestrator.approveFallback(decision: .useCloud) }
                        .buttonStyle(.borderedProminent).tint(.orange).frame(maxWidth: .infinity)
                    Button("İptal") { orchestrator.approveFallback(decision: .cancel) }
                        .buttonStyle(.bordered).frame(maxWidth: .infinity)
                }
            }
        }
        .padding(24).background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 20)).frame(width: 280)
    }
    
    private var permissionApprovalModal: some View {
        ZStack {
            Color.black.opacity(0.3).ignoresSafeArea()
            VStack(spacing: 24) {
                Image(systemName: "lock.shield.fill")
                    .font(.title).foregroundStyle(.blue)
                Text("İzin Gerekli (\(sessionState.permissionAppTarget ?? "Uygulama"))").font(.headline)
                Text("EliteAgent'ın işlemi tamamlayabilmesi için otomasyon izni gerekiyor:\n\nSistem Ayarları → Gizlilik → Otomasyon → EliteAgent → \(sessionState.permissionAppTarget ?? "Uygulama") ✓")
                    .font(.caption).multilineTextAlignment(.center)
                    .padding(.horizontal)
                
                VStack(spacing: 12) {
                    Button("Ayarları Aç") {
                        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Automation") {
                            NSWorkspace.shared.open(url)
                        }
                    }
                    .buttonStyle(.borderedProminent).tint(.blue).frame(maxWidth: .infinity)
                    
                    Button("Tamam") {
                        sessionState.requiresPermissionAcknowledgement = false
                    }
                    .buttonStyle(.bordered).frame(maxWidth: .infinity)
                }
            }
        }
        .padding(24).background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 20)).frame(width: 320)
    }
}

// MARK: - HIG Refined Subviews

struct ChatBubble: View {
    let message: ChatMessage
    @State private var parseError: Bool = false
    
    var body: some View {
        HStack {
            if message.role == .user { Spacer() }
            
            VStack(alignment: message.role == .user ? .trailing : .leading, spacing: 8) {
                if shouldHideMessage {
                    EmptyView()
                } else if let report = tryParseReport(message.content) {
                    ResearchReportView(report: report)
                        .frame(maxWidth: 600)
                } else if parseError {
                    fallbackView
                } else {
                    standardTextView
                }
            }
            .frame(idealWidth: 480, alignment: message.role == .user ? .trailing : .leading)
            .accessibilityLabel("\(message.role == .user ? "Siz" : "Asistan"): \(message.content)")
            
            if message.role == .assistant { Spacer() }
        }
    }
    
    private var shouldHideMessage: Bool {
        let content = message.content.lowercased()
        // 1. Hide </final> tags and tool_code blocks
        if content.contains("</final>") || content.contains("```tool_code") {
            return true
        }
        
        // 2. Hide tool calls/actions
        if content.contains("\"action\":") || content.contains("\"tool\"") {
            // EXCEPTION: Show progress messages
            let icons = ["🔍", "📡", "🧠", "📊", "🎯"]
            for icon in icons {
                if content.contains(icon) { return false }
            }
            return true
        }
        
        return false
    }
    
    private var standardTextView: some View {
        Text(message.content)
            .font(.subheadline)
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(
                message.role == .user ? 
                AnyShapeStyle(Color.accentColor) : 
                AnyShapeStyle(Color.secondary.opacity(0.1))
            )
            .foregroundStyle(message.role == .user ? .white : .primary)
            .cornerRadius(14, antialiased: true)
    }
    
    private var fallbackView: some View {
        VStack(alignment: .leading, spacing: 10) {
            standardTextView
                .font(.caption)
                .foregroundStyle(.secondary)
            
            Button {
                NotificationCenter.default.post(name: NSNotification.Name("RetryParse"), object: message.id)
            } label: {
                Label("🔄 Yeniden Dene (JSON Parse Hatası)", systemImage: "arrow.clockwise")
                    .font(.caption.bold())
                    .foregroundStyle(.orange)
            }
            .buttonStyle(.plain)
            .padding(.leading, 14)
        }
    }

    private func tryParseReport(_ content: String) -> ResearchReport? {
        let jsonStr = ThinkParser.extractJSONrobustly(content)
        
        // Final sanity check before attempting decode
        guard jsonStr.contains("\"report\"") || jsonStr.contains("\"recommendation\"") else { return nil }
        
        guard let data = jsonStr.data(using: .utf8) else { return nil }
        
        do {
            let report = try JSONDecoder().decode(ResearchReport.self, from: data)
            DispatchQueue.main.async { self.parseError = false }
            return report
        } catch {
            // Only set parse error if it definitely intended to be a report but failed
            if content.contains("\"report\"") || content.contains("\"title\"") {
                DispatchQueue.main.async { self.parseError = true }
            }
            print("[ResearchReportView] JSON parse failed: \(error)")
            return nil
        }
    }
}

// The following structures are kept for functional completeness but with refined HIG styles
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
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
    }
}

struct ModelPickerMenu: View {
    @ObservedObject var modelPickerVM: ModelPickerViewModel
    var body: some View {
        Menu {
            Section(modelPickerVM.hasTitanEngine ? "LOCAL - TITAN ENGINE" : "LOCAL TITAN") {
                ForEach(modelPickerVM.filteredLocalModels) { model in
                    Button { modelPickerVM.selectModel(model) } label: {
                        Label(model.name, systemImage: model.icon)
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
                Text(modelPickerVM.selected?.name ?? "Model Seç")
                    .font(.subheadline.bold())
                Image(systemName: "chevron.up.chevron.down")
                    .font(.caption2)
            }
            .foregroundStyle(.primary)
        }
        .menuStyle(.button)
    }
}

// MARK: - v9.6 Self-Healing UI Components

struct HealthStatusBadge: View {
    @StateObject private var watchdog = LocalModelWatchdog.shared
    
    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: watchdog.status.icon)
                .font(.caption2)
            Text(watchdog.status.rawValue)
                .font(.caption2.bold())
                .textCase(.uppercase)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 2)
        .background(statusColor.opacity(0.1), in: Capsule())
        .foregroundStyle(statusColor)
        .help(watchdog.metrics.diagnostic)
    }
    
    private var statusColor: Color {
        switch watchdog.status {
        case .healthy: return .green
        case .degraded: return .orange
        case .critical: return .red
        }
    }
}

struct StatusIndicator: View {
    let status: AgentStatus
    let isModelSelected: Bool
    let hasMessages: Bool
    
    var body: some View {
        HStack(spacing: 8) {
            Circle().fill(statusColor).frame(width: 8, height: 8)
                .shadow(color: statusColor.opacity(0.4), radius: 3)
            if status == .working {
                Text("Düşünüyor...").font(.caption2).foregroundStyle(.secondary)
            }
        }
    }
    
    private var statusColor: Color {
        // v7.9.0: 3-State Logic (Red -> Orange -> Green)
        if !isModelSelected { return .red }
        if !hasMessages { return .orange }
        
        switch status {
        case .error: return .red
        default: return .green
        }
    }
}

struct SessionStatsView: View {
    @ObservedObject var orchestrator: Orchestrator
    @Binding var showingSettings: Bool
    var body: some View {
        HStack(spacing: 12) {
            Text("$\(String(format: "%.4f", NSDecimalNumber(decimal: orchestrator.costToday).doubleValue))")
                .font(.system(.footnote, design: .monospaced))
                .padding(.horizontal, 6).padding(.vertical, 2)
                .background(.secondary.opacity(0.1), in: RoundedRectangle(cornerRadius: 4))
            Button { showingSettings.toggle() } label: { Image(systemName: "gearshape") }
                .buttonStyle(.plain).foregroundStyle(.secondary)
        }
    }
}
@MainActor
struct FooterButton: View {
    let action: () -> Void
    @State private var isHovering = false
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: "square.and.pencil")
                    .font(.system(size: 14, weight: .medium))
                Text("Yeni Sohbet")
                    .font(.subheadline)
            }
            .foregroundStyle(.secondary)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity, alignment: .leading) // Align leading for native sidebar feel
            .background(isHovering ? Color.primary.opacity(0.06) : Color.clear)
            .cornerRadius(8)
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 8)
        .padding(.vertical, 8)
        .onHover { hovering in
            withAnimation(.easeOut(duration: 0.1)) {
                isHovering = hovering
            }
        }
        .keyboardShortcut("n", modifiers: .command)
        .help("Yeni sohbet başlat (⌘N)")
        .accessibilityLabel("Yeni sohbet")
        .accessibilityHint("⌘N kısayolu ile de açılabilir")
    }
}
struct StepIcon: View {
    let status: String
    var body: some View {
        switch status {
        case "done": return Image(systemName: "checkmark.circle.fill").foregroundColor(.green)
        case "running": return Image(systemName: "arrow.trianglehead.2.clockwise").foregroundColor(.yellow)
        case "failed": return Image(systemName: "xmark.circle.fill").foregroundColor(.red)
        default: return Image(systemName: "circle").foregroundColor(.secondary)
        }
    }
}
