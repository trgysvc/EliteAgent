import SwiftUI
import Combine
import EliteAgentCore

public struct GlassEffectStyle: Sendable {
    public static let regular = GlassEffectStyle()
    public func interactive() -> GlassEffectStyle { return self }
}

public extension View {
    func glassEffect(_ style: GlassEffectStyle) -> some View {
        // macOS 26 Liquid Glass compatibility simulation for macOS 14 builder
        self.background(Material.regularMaterial)
    }
}

public struct ChatWindowView: View {
    @ObservedObject public var orchestrator: Orchestrator
    @ObservedObject public var modelPickerVM: ModelPickerViewModel
    @State private var promptText: String = ""
    @StateObject private var modelSetup = ModelSetupManager.shared
    @State private var showingModelSetup: Bool = false
    @State private var showingSettings: Bool = false
    @State private var showingTitanAssistant: Bool = false
    
    // v7.7.0 Production Process Visualization
    @StateObject private var processVM = ChatProcessViewModel()
    
    // v7.8.0 Centralized State Sync
    @State private var sessionState = AISessionState.shared
    
    // v7.6.0 File Attachment UI (Legacy bridge for input field)
    @State private var attachedFileURL: URL? = nil
    @State private var showingFileImporter = false
    @State private var isAnimatingAttachment = false
    @State private var isScanningDocument = false
    @State private var isDraggingOver = false // v7.7.0 HIG Feedback
    
    public init(orchestrator: Orchestrator, modelPickerVM: ModelPickerViewModel) {
        self.orchestrator = orchestrator
        self.modelPickerVM = modelPickerVM
    }
    
    public var body: some View {
        NavigationSplitView {
            // SIDEBAR: Recent Tasks / Past Sessions
            List(orchestrator.pastSessions, selection: $orchestrator.selectedSessionID) { session in
                Button {
                    orchestrator.selectSession(session)
                } label: {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(session.title)
                            .font(.headline)
                            .lineLimit(1)
                        
                        HStack {
                            Text(session.createdAt.formatted(.relative(presentation: .named)))
                            Spacer()
                            Text(session.metadata.cost > 0 ? "$\(String(format: "%.3f", NSDecimalNumber(decimal: session.metadata.cost).doubleValue))" : "")
                        }
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 4)
                }
                .buttonStyle(.plain)
                .listRowSeparator(.hidden)
                .listRowBackground(
                    RoundedRectangle(cornerRadius: 10)
                        .fill(orchestrator.selectedSessionID == session.id ? Color.accentColor.opacity(0.15) : Color.clear)
                        .padding(.horizontal, 4)
                )
            }
            .navigationTitle("Recent Tasks")
            .toolbar {
                ToolbarItem {
                    Button(action: { orchestrator.startNewConversation() }) {
                        Image(systemName: "square.and.pencil")
                    }
                    .help("New Conversation")
                }
            }
        } detail: {
            ZStack {
                // BACKGROUND: Neural Sight Metal Engine
                VisualizerView()
                    .ignoresSafeArea()
                    .opacity(orchestrator.status == .idle ? 0.2 : 0.6)
                    .animation(.easeInOut(duration: 1.0), value: orchestrator.status)
                
                VStack(spacing: 0) {
                    // TOP BAR: Model Selection & Stats
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            ModelPickerMenu(modelPickerVM: modelPickerVM)
                            
                            if sessionState.isFallbackActive {
                                HStack(spacing: 4) {
                                    Image(systemName: "cloud.fill")
                                    Text("\(sessionState.activeProvider) - Cloud Fallback")
                                }
                                .font(.system(size: 8, weight: .bold))
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color.orange, in: Capsule())
                                .foregroundStyle(.white)
                                .transition(.move(edge: .top).combined(with: .opacity))
                            }
                        }
                        
                        Spacer()
                        
                        if isScanningDocument {
                            HStack(spacing: 8) {
                                ProgressView()
                                    .controlSize(.small)
                                Text("DocEye Scanning...")
                                    .font(.caption.bold())
                                    .foregroundStyle(Color.accentColor)
                            }
                            .padding(.horizontal, 10)
                            .padding(.vertical, 4)
                            .background(Color.accentColor.opacity(0.1), in: Capsule())
                            .transition(.push(from: .top))
                        } else {
                            StatusIndicator(status: orchestrator.status)
                        }
                        
                        Spacer()
                        
                        SessionStatsView(orchestrator: orchestrator, showingSettings: $showingSettings)
                    }
                    .padding()
                    .glassEffect(.regular)
                    
                    // CHAT AREA: Conversational Bubbles
                    ScrollViewReader { proxy in
                        ScrollView {
                            VStack(spacing: 20) {
                                ForEach(orchestrator.currentMessages) { message in
                                    ChatBubble(message: message)
                                        .id(message.id)
                                }
                                
                                // ACTIVE WORKFLOW: Show steps while working
                                if !orchestrator.steps.isEmpty && orchestrator.status != .idle {
                                    WorkflowView(orchestrator: orchestrator)
                                        .padding(.horizontal)
                                        .transition(.opacity.combined(with: .move(edge: .bottom)))
                                }
                            }
                            .padding()
                        }
                        .onChange(of: orchestrator.currentMessages.count) {
                            if let last = orchestrator.currentMessages.last {
                                withAnimation { proxy.scrollTo(last.id, anchor: .bottom) }
                            }
                        }
                    }
                    .overlay {
                        // v7.7.0 Apple HIG Drop Overlay (New Component)
                        if processVM.currentState == .idle {
                            FileUploadZone { url in
                                processVM.startUpload(fileURL: url, actor: InferenceActor.shared)
                            }
                            .opacity(isDraggingOver ? 1 : 0)
                            .allowsHitTesting(isDraggingOver)
                        }
                    }
                    .overlay {
                        // v7.7.0 Process Visualization Overlay
                        processOverlay(viewModel: processVM)
                    }
                    .overlay {
                        // v7.8.0 Fallback Approval Modal
                        if sessionState.requiresUserAcknowledgement {
                            fallbackApprovalModal
                        }
                    }
                    
                    // INPUT AREA: Floating Action Area
                    VStack(spacing: 8) {
                        // v7.6.0 Attached File Chip (Appears smoothly)
                        if let file = attachedFileURL {
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
                            .overlay(Capsule().strokeBorder(Color.accentColor.opacity(0.3), lineWidth: 1))
                            .transition(.move(edge: .bottom).combined(with: .opacity))
                        }
                        
                        HStack(spacing: 12) {
                            // v7.7.0 Attachment Button (+) - Refined Appearance
                            Button {
                                showingFileImporter = true
                            } label: {
                                ZStack {
                                    Circle()
                                        .fill(Color.accentColor.opacity(0.15))
                                        .frame(width: 32, height: 32)
                                    
                                    Image(systemName: "plus")
                                        .font(.system(size: 16, weight: .bold))
                                        .foregroundStyle(Color.accentColor)
                                }
                                .scaleEffect(isAnimatingAttachment ? 1.2 : 1.0)
                            }
                            .buttonStyle(.plain)
                            .help("Attach Document")
                            
                            TextField("Ask anything...", text: $promptText)
                                .textFieldStyle(.plain)
                                .padding(10)
                            
                            Button(action: submitTask) {
                                Image(systemName: "arrow.up.circle.fill")
                                    .font(.system(size: 30))
                                    .symbolRenderingMode(.hierarchical)
                            }
                            .buttonStyle(.plain)
                            .disabled((promptText.isEmpty && attachedFileURL == nil) || orchestrator.status == .working || sessionState.requiresUserAcknowledgement || sessionState.isInputLocked)
                            .keyboardShortcut(.return, modifiers: .command)
                        }
                        .padding(.horizontal, 8)
                        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 20))
                    }
                    .padding()
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
                allowedContentTypes: [.pdf, .plainText, .text, .swiftSource, .xml, .json],
                allowsMultipleSelection: false
            ) { result in
                switch result {
                case .success(let urls):
                    if let url = urls.first {
                        processVM.startUpload(fileURL: url, actor: InferenceActor.shared)
                    }
                case .failure(let error):
                    print("[UI] File picker failed: \(error)")
                }
            }
            .onAppear {
                Task {
                    await modelPickerVM.loadModels()
                    if !modelSetup.isModelReady {
                        try? await Task.sleep(nanoseconds: 800_000_000)
                        DispatchQueue.main.async {
                            self.showingTitanAssistant = true
                        }
                    }
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
            .onDisappear {
                processVM.cancel()
            }
        }
    }
    
    private func submitTask() {
        var text = promptText
        
        // v7.6.0 Handle File Ingestion
        if let fileURL = attachedFileURL {
            // Append file path to prompt to trigger DocEye
            let path = fileURL.path
            text = "'\(path)' " + text
            
            // Auto-complete a generic request if text is empty
            if promptText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                text = "'\(path)' bu dökümanı özetle."
            }
        }
        
        guard !text.isEmpty || attachedFileURL != nil else { return }
        
        promptText = ""
        withAnimation { attachedFileURL = nil }
        
        Task {
            if text.contains(".pdf") || text.contains(".txt") {
                withAnimation { isScanningDocument = true }
            }
            
            do {
                try await orchestrator.submitTask(prompt: text)
            } catch {
                print("[ERROR] Task submission failed: \(error)")
            }
            
            withAnimation { isScanningDocument = false }
        }
    }
    
    // MARK: - Approval Modal
    private var fallbackApprovalModal: some View {
        ZStack {
            Color.black.opacity(0.4).ignoresSafeArea()
            
            VStack(spacing: 20) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 40))
                    .foregroundStyle(.orange)
                
                Text("Yerel Model Hazır Değil")
                    .font(.headline)
                
                if let reason = sessionState.fallbackReason {
                    Text(reason)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                
                Text("Bulut modeli (Claude 3.5) ile devam etmek istiyor musunuz?")
                    .font(.subheadline)
                    .multilineTextAlignment(.center)
                
                VStack(spacing: 10) {
                    if let reason = sessionState.fallbackReason, reason.contains("Eksik") {
                        Button {
                            sessionState.resetForNewTask()
                            showingTitanAssistant = true
                        } label: {
                            HStack {
                                Image(systemName: "arrow.down.circle.fill")
                                Text("Titan Motorunu Kur (İndir)")
                            }
                            .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(.blue)
                    }
                    
                    Button {
                        orchestrator.approveFallback(decision: .useCloud)
                    } label: {
                        Text("Bulut ile Devam Et (Claude)")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.orange)
                    
                    Button {
                        orchestrator.approveFallback(decision: .cancel)
                    } label: {
                        Text("İptal Et")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                }
            }
            .padding(24)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 24))
            .frame(width: 300)
            .shadow(radius: 20)
        }
    }
}

// MARK: - Subviews

struct ChatBubble: View {
    let message: ChatMessage
    
    var body: some View {
        HStack {
            if message.role == .user { Spacer() }
            
            VStack(alignment: message.role == .user ? .trailing : .leading, spacing: 4) {
                if let analysis = message.audioAnalysis {
                    MusicDNACard(analysis: analysis) {
                        if let path = analysis.reportPath {
                            NSWorkspace.shared.open(URL(fileURLWithPath: path))
                        }
                    }
                    .frame(width: 320)
                } else {
                    Text(message.content)
                        .padding(12)
                        .background(
                            message.role == .user ? 
                            AnyShapeStyle(Color.accentColor) : 
                            AnyShapeStyle(.ultraThinMaterial)
                        )
                        .cornerRadius(16)
                        .foregroundColor(message.role == .user ? .white : .primary)
                }
            }
            .frame(maxWidth: 500, alignment: message.role == .user ? .trailing : .leading)
            
            if message.role == .assistant { Spacer() }
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
                        Text(step.name)
                            .font(.subheadline)
                        Spacer()
                        Text(step.latency)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .padding()
        } label: {
            HStack {
                Label("Agent Workflow", systemImage: "cpu")
                    .font(.caption.bold())
                Text("(\(orchestrator.steps.count) steps completed)")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .glassEffect(.regular)
        .cornerRadius(12)
    }
}

struct ModelPickerMenu: View {
    @ObservedObject var modelPickerVM: ModelPickerViewModel
    @State private var showingPopover = false
    @FocusState private var isSearchFocused: Bool
    
    var body: some View {
        Button {
            showingPopover.toggle()
        } label: {
            Label(modelPickerVM.selected?.name ?? "Select Model", systemImage: modelPickerVM.selected?.icon ?? "cpu.fill")
                .font(.subheadline.bold())
        }
        .buttonStyle(.bordered)
        .popover(isPresented: $showingPopover, arrowEdge: .bottom) {
            VStack(spacing: 0) {
                // Search Header
                HStack {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(.secondary)
                    TextField("Search models...", text: $modelPickerVM.searchText)
                        .textFieldStyle(.plain)
                        .focused($isSearchFocused)
                    
                    if !modelPickerVM.searchText.isEmpty {
                        Button { modelPickerVM.searchText = "" } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding()
                .background(.ultraThinMaterial)
                
                Divider()
                
                // Model List
                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        if !modelPickerVM.filteredLocalModels.isEmpty {
                            Text("LOCAL — TITAN ENGINE")
                                .font(.caption2.bold())
                                .foregroundStyle(.secondary)
                                .padding(.horizontal)
                                .padding(.top, 8)
                            
                            ForEach(modelPickerVM.filteredLocalModels) { model in
                                ModelRow(model: model, isSelected: modelPickerVM.selected?.id == model.id) {
                                    modelPickerVM.selectModel(model)
                                    showingPopover = false
                                }
                            }
                        }
                        
                        if !modelPickerVM.filteredOllamaModels.isEmpty {
                            Text("BRIDGE — OLLAMA / LOCAL")
                                .font(.caption2.bold())
                                .foregroundStyle(.secondary)
                                .padding(.horizontal)
                                .padding(.top, 8)
                            
                            ForEach(modelPickerVM.filteredOllamaModels) { model in
                                ModelRow(model: model, isSelected: modelPickerVM.selected?.id == model.id) {
                                    modelPickerVM.selectModel(model)
                                    showingPopover = false
                                }
                            }
                        }
                        
                        if !modelPickerVM.filteredCloudModels.isEmpty {
                            Text("CLOUD — OPENROUTER")
                                .font(.caption2.bold())
                                .foregroundStyle(.secondary)
                                .padding(.horizontal)
                                .padding(.top, 8)
                            
                            ForEach(modelPickerVM.filteredCloudModels) { model in
                                ModelRow(model: model, isSelected: modelPickerVM.selected?.id == model.id) {
                                    modelPickerVM.selectModel(model)
                                    showingPopover = false
                                }
                            }
                        }
                        
                        if modelPickerVM.filteredLocalModels.isEmpty && modelPickerVM.filteredCloudModels.isEmpty {
                            ContentUnavailableView("No Models Found", systemImage: "magnifyingglass", description: Text("Try a different search term."))
                                .frame(height: 200)
                        }
                    }
                    .padding(.bottom)
                }
                .frame(minWidth: 320, maxHeight: 450)
            }
            .onAppear {
                DispatchQueue.main.async {
                    isSearchFocused = true
                }
            }
        }
    }
}

struct ModelRow: View {
    let model: ModelSource
    let isSelected: Bool
    let action: () -> Void
    @State private var isHovering = false
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: model.icon)
                    .font(.title3)
                    .foregroundStyle(isSelected ? .white : .accentColor)
                    .frame(width: 24)
                
                VStack(alignment: .leading, spacing: 2) {
                    Text(model.name)
                        .font(.subheadline.bold())
                        .foregroundStyle(isSelected ? .white : .primary)
                    
                    if case .openRouter(_, _, let isFree, let context, let prompt, _) = model {
                        HStack {
                            if isFree {
                                Text("FREE")
                                    .font(.system(size: 8, weight: .black))
                                    .padding(.horizontal, 4)
                                    .background(.green.opacity(0.2), in: Capsule())
                                    .foregroundStyle(.green)
                            } else if let p = prompt {
                                Text("$\(NSDecimalNumber(decimal: p).stringValue)/M")
                                    .font(.system(size: 9, design: .monospaced))
                            }
                            Text("\(context)k ctx")
                                .font(.system(size: 9))
                                .foregroundStyle(.secondary)
                        }
                    } else {
                        Text("Titan Optimized")
                            .font(.system(size: 9))
                            .foregroundStyle(isSelected ? .white.opacity(0.8) : .secondary)
                    }
                }
                
                Spacer()
                
                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.white)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(isSelected ? Color.accentColor : (isHovering ? Color.accentColor.opacity(0.1) : Color.clear))
            )
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 8)
        .onHover { hovering in
            isHovering = hovering
        }
    }
}

struct StatusIndicator: View {
    let status: AgentStatus
    
    var body: some View {
        HStack {
            Circle()
                .fill(statusColor)
                .frame(width: 8, height: 8)
            
            if isStatusWaiting {
                Text(statusText)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
    }
    
    private var isStatusWaiting: Bool {
        switch status {
        case .working, .waiting, .waitingLLM, .awaitingFallbackApproval: return true
        default: return false
        }
    }
    
    private var statusText: String {
        switch status {
        case .working: return "Thinking..."
        case .awaitingFallbackApproval: return "Approval Needed"
        default: return "Waiting..."
        }
    }
    
    private var statusColor: Color {
        switch status {
        case .idle: return .green
        case .working: return .yellow
        case .waiting, .waitingLLM: return .orange
        case .healing: return .purple
        case .error: return .red
        case .awaitingFallbackApproval: return .orange
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
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 6))
            
            Button(action: { showingSettings.toggle() }) {
                Image(systemName: "gearshape.fill")
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            
            Button(action: { NSApp.terminate(nil) }) {
                Image(systemName: "power")
                    .foregroundColor(.red.opacity(0.8))
            }
            .buttonStyle(.plain)
            .help("Quit Elite Agent")
        }
    }
}

struct StepIcon: View {
    let status: String
    var body: some View {
        switch status {
        case "done": return AnyView(Image(systemName: "checkmark.circle.fill").foregroundColor(.green))
        case "running": return AnyView(Image(systemName: "arrow.trianglehead.2.clockwise").foregroundColor(.yellow).symbolEffect(.pulse))
        case "failed": return AnyView(Image(systemName: "xmark.circle.fill").foregroundColor(.red))
        default: return AnyView(Image(systemName: "circle").foregroundColor(.secondary))
        }
    }
}
