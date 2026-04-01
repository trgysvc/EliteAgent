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
                        ModelPickerMenu(modelPickerVM: modelPickerVM)
                        
                        Spacer()
                        
                        StatusIndicator(status: orchestrator.status)
                        
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
                    
                    // INPUT AREA: Floating Action Area
                    HStack(spacing: 12) {
                        TextField("Ask anything...", text: $promptText)
                            .textFieldStyle(.plain)
                            .padding(10)
                        
                        Button(action: submitTask) {
                            Image(systemName: "arrow.up.circle.fill")
                                .font(.system(size: 30))
                                .symbolRenderingMode(.hierarchical)
                        }
                        .buttonStyle(.plain)
                        .disabled(promptText.isEmpty || orchestrator.status == .working)
                        .keyboardShortcut(.return, modifiers: .command)
                    }
                    .padding(.horizontal, 8)
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 20))
                    .padding()
                }
            }
            .sheet(isPresented: $showingSettings) {
                SettingsView(orchestrator: orchestrator)
            }
            .sheet(isPresented: $showingTitanAssistant) {
                ModelSetupView()
            }
        }
        .onAppear {
            Task { @MainActor in
                await modelPickerVM.loadModels()
                if !modelSetup.isModelReady {
                    try? await Task.sleep(nanoseconds: 800_000_000)
                    self.showingTitanAssistant = true
                }
            }
        }
    }
    
    private func submitTask() {
        let text = promptText
        guard !text.isEmpty else { return }
        promptText = ""
        Task {
            try? await orchestrator.submitTask(prompt: text)
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
    
    var body: some View {
        Menu {
            Section("Local — MLX") {
                ForEach(modelPickerVM.localModels) { model in
                    Button { modelPickerVM.selectModel(model) } label: {
                        Label(model.name, systemImage: "cpu")
                    }
                }
            }
            Divider()
            Section("Cloud — OpenRouter") {
                ForEach(modelPickerVM.cloudModels) { model in
                    Button { modelPickerVM.selectModel(model) } label: {
                        Label(model.name, systemImage: "cloud")
                    }
                }
            }
        } label: {
            Label(modelPickerVM.selected?.name ?? "Select Model", systemImage: modelPickerVM.selected?.icon ?? "cpu.fill")
                .font(.subheadline.bold())
        }
        .menuStyle(.button)
        .buttonStyle(.bordered)
    }
}

struct StatusIndicator: View {
    let status: AgentStatus
    
    var body: some View {
        HStack {
            Circle()
                .fill(statusColor)
                .frame(width: 8, height: 8)
            
            if status == .working || status == .waiting {
                Text(status == .working ? "Thinking..." : "Waiting...")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
    }
    
    private var statusColor: Color {
        switch status {
        case .idle: return .green
        case .working: return .yellow
        case .waiting, .waitingLLM: return .orange
        case .healing: return .purple
        case .error: return .red
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
