import SwiftUI
import Combine

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
                                    HStack {
                                        Label(model.name, systemImage: "cloud")
                                        Spacer()
                                        if model.isFree {
                                            Text("FREE")
                                                .font(.caption)
                                                .foregroundStyle(.green)
                                        }
                                    }
                                }
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
                    
                    Text("Today: $\(String(format: "%.2f", NSDecimalNumber(decimal: orchestrator.costToday).doubleValue))")
                        .font(.footnote)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 8))
                        .foregroundStyle(.secondary)
                }
                .padding()
                
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
            }
        }
    }
    
    private var statusColor: Color {
        switch orchestrator.status {
        case .idle: return .green
        case .working: return .yellow
        case .waiting, .waitingLLM: return .orange
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
        promptText = ""
        Task {
            try? await orchestrator.submitTask(prompt: text)
        }
    }
}
