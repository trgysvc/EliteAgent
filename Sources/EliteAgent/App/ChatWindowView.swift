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
    @State private var showingAnalytics: Bool = false
    @State private var showingModelSetup: Bool = false
    @State private var showingSettings: Bool = false
    @State private var showingTitanAssistant: Bool = false
    
    public init(orchestrator: Orchestrator, modelPickerVM: ModelPickerViewModel) {
        self.orchestrator = orchestrator
        self.modelPickerVM = modelPickerVM
    }
    
    public var body: some View {
        NavigationSplitView {
            // Sidebar (Task History) - gets Liquid Glass automatically on Tahoe
            List {
                Text("Recent Tasks")
                    .font(.headline)
            }
            .navigationTitle("History")
        } detail: {
            ZStack {
                // Phase 2: Neural Sight Metal Engine
                VisualizerView()
                    .ignoresSafeArea()
                    .opacity(orchestrator.status == .idle ? 0.3 : 0.8) // Dimmable based on activity
                    .animation(.easeInOut(duration: 1.0), value: orchestrator.status)
                
                VStack(spacing: 0) {
                // Toolbar
                HStack {
                    Menu {
                        Section("Local — MLX") {
                            ForEach(modelPickerVM.localModels) { model in
                                Button {
                                    modelPickerVM.selectModel(model)
                                } label: {
                                    HStack {
                                        Label(model.name, systemImage: "cpu")
                                        Spacer()
                                        if case .localMLX(_, _, let ram, _) = model {
                                            Text("\(ram)GB")
                                                .foregroundStyle(.secondary)
                                                .font(.caption)
                                        }
                                    }
                                }
                            }
                        }
                        
                        Divider()
                        
                        Section("OpenRouter — Cloud") {
                            ForEach(modelPickerVM.cloudModels) { model in
                                Button {
                                    modelPickerVM.selectModel(model)
                                } label: {
                                    VStack(alignment: .leading, spacing: 2) {
                                        HStack {
                                            Label(model.name, systemImage: "cloud")
                                            Spacer()
                                            if model.isFree {
                                                Text("FREE")
                                                    .font(.caption)
                                                    .foregroundStyle(.green)
                                            }
                                        }
                                        
                                        if case .openRouter(_, _, _, _, let prompt, let completion) = model, let p = prompt, let c = completion {
                                            HStack(spacing: 8) {
                                                Text("In: \(formatPrice(p))")
                                                Text("Out: \(formatPrice(c))")
                                            }
                                            .font(.system(size: 9, weight: .medium, design: .monospaced))
                                            .foregroundStyle(.secondary)
                                        }
                                    }
                                }
                            }
                        }
                        
                        Divider()
                        
                        Section("Custom Connections") {
                            ForEach(modelPickerVM.models.filter { if case .custom = $0 { return true }; return false }) { model in
                                Button {
                                    modelPickerVM.selectModel(model)
                                } label: {
                                    Label(model.name, systemImage: model.icon)
                                }
                            }
                            
                            Button(action: { showingModelSetup.toggle() }) {
                                Label("Add Custom Model...", systemImage: "plus.circle")
                            }
                        }
                    } label: {
                        Label(modelPickerVM.selected?.name ?? "Select Model", systemImage: modelPickerVM.selected?.icon ?? "cpu.fill")
                            .labelStyle(.titleAndIcon)
                    }
                    .menuStyle(.button)
                    .buttonStyle(.bordered)
                    
                    Spacer()
                    
                    HStack {
                        Circle()
                            .fill(statusColor)
                            .frame(width: 8, height: 8)
                        
                        if orchestrator.status == .working || orchestrator.status == .waiting {
                            Image(systemName: orchestrator.status == .working ? "arrow.2.circlepath" : "clock")
                                .symbolEffect(.pulse, isActive: orchestrator.status == .working)
                        }
                    }
                    
                    Spacer()
                    
                    HStack(spacing: 12) {
                        Text("Tokens: \(orchestrator.promptTokens) / \(orchestrator.completionTokens)")
                            .font(.footnote)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 8))
                        
                        Text("Cost: $\(String(format: "%.4f", NSDecimalNumber(decimal: orchestrator.costToday).doubleValue))")
                            .font(.footnote)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 8))
                        
                        Button(action: { showingSettings.toggle() }) {
                            Image(systemName: "gear")
                                .font(.body)
                        }
                        .buttonStyle(.bordered)
                        .help("Settings")
                        
                        Button(action: { NSApp.terminate(nil) }) {
                            Image(systemName: "power")
                                .foregroundColor(.red)
                        }
                        .buttonStyle(.bordered)
                        .help("Quit Elite Agent")
                    }
                    .foregroundStyle(.secondary)
                }
                .padding()
                .sheet(isPresented: $showingModelSetup) {
                    let defaultVaultPath = URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent(".eliteagent/vault.plist")
                    if (try? VaultManager(configURL: defaultVaultPath)) != nil {
                        ModelSetupView()
                    }
                }
                .sheet(isPresented: $showingSettings) {
                    SettingsView(orchestrator: orchestrator)
                }
                .sheet(isPresented: $showingTitanAssistant) {
                    ModelSetupView()
                }
                
                Divider()
                
                // Message Area
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        if !orchestrator.currentTask.isEmpty {
                            HStack {
                                Spacer()
                                Text(orchestrator.currentTask)
                                    .padding()
                                    .background(.blue.opacity(0.15))
                                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
                            }
                        }
                        
                        ForEach(orchestrator.steps) { step in
                            HStack {
                                stepIcon(for: step.status)
                                Text(step.name)
                                Spacer()
                                Text(step.latency)
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            .padding(.horizontal)
                        }
                        
                        ForEach(orchestrator.thinkBlocks, id: \.timestamp) { block in
                            DisclosureGroup("Think Block") {
                                Text(block.content)
                                    .font(.system(.body, design: .monospaced))
                                    .padding()
                            }
                            .glassEffect(.regular)
                            .padding(.horizontal)
                        }
                    }
                    .padding(.vertical)
                }
                // Removed explicit .animation() from ScrollView to prevent layout recursion (0x5)
                // in SwiftUI-AppKit hybrid bridging.
                
                // Floating Action Area
                HStack {
                    TextField("Ask anything...", text: $promptText)
                        .textFieldStyle(.plain)
                    
                    Button(action: submitTask) {
                        Image(systemName: "arrow.up.circle.fill")
                            .font(.title2)
                            .foregroundColor(.accentColor)
                    }
                    .buttonStyle(.plain)
                    .keyboardShortcut(.return, modifiers: .command)
                }
                .padding(12)
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
                .padding()
            } // Close VStack
        } // Close ZStack
    } // Close Detail
    .onAppear {
        Task { @MainActor in
            await modelPickerVM.loadModels()
            
            // TITAN ONBOARDING: Show assistant if local model is missing
            // Use a safer, more explicit MainActor boundary and bypass recursion (0x5)
            if !modelSetup.isModelReady {
                try? await Task.sleep(nanoseconds: 800_000_000) // 0.8s wait for stable layout
                self.showingTitanAssistant = true
            }
        }
    }
} // Close Body
    
    private var statusColor: Color {
        switch orchestrator.status {
        case .idle: return .green
        case .working: return .yellow
        case .waiting, .waitingLLM: return .orange
        case .healing: return .purple
        case .error: return .red
        }
    }
    
    @ViewBuilder
    private func stepIcon(for status: String) -> some View {
        switch status {
        case "done":
            Image(systemName: "checkmark.circle.fill")
                .foregroundColor(.green)
        case "running":
            Image(systemName: "arrow.trianglehead.2.clockwise")
                .foregroundColor(.yellow)
                .symbolEffect(.pulse, isActive: true)
        case "healing":
            Image(systemName: "rays")
                .foregroundColor(.purple)
                .symbolEffect(.pulse, isActive: true)
        case "failed":
            Image(systemName: "xmark.circle.fill")
                .foregroundColor(.red)
        default:
            Image(systemName: "circle")
                .foregroundColor(.secondary)
        }
    }
    
    private func submitTask() {
        let text = promptText
        guard !text.isEmpty else { return }
        
        // Swift 6: structured concurrency
        promptText = ""
        Task {
            do {
                try await orchestrator.submitTask(prompt: text)
            } catch {
                print("[UI] Task submission failed: \(error)")
            }
        }
    }
    
    private func formatPrice(_ price: Decimal) -> String {
        // Show price per 1M tokens for better readability in small UI
        let perMillion = price * 1_000_000
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencySymbol = "$"
        formatter.maximumFractionDigits = 2
        return (formatter.string(from: perMillion as NSNumber) ?? "$0") + "/1M"
    }
}
