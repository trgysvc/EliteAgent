import SwiftUI

public struct MenuBarView: View {
    @ObservedObject public var orchestrator: Orchestrator
    @State private var promptText: String = ""
    @State private var selectedCategory: String? = nil
    @State private var isVisible: Bool = false
    @FocusState private var isInputFocused: Bool
    
    public init(orchestrator: Orchestrator) {
        self.orchestrator = orchestrator
    }
    
    public var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Status Header
            HStack {
                statusDot
                
                Text(orchestrator.status.rawValue.capitalized)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                
                Spacer()
                
                Button(action: openChat) {
                    Image(systemName: "uiwindow.split.2x1")
                }
                .buttonStyle(PlainButtonStyle())
                .help("Open Full Chat (⌘K)")
                .keyboardShortcut("k", modifiers: .command)
            }
            
            // Input Field
            TextField("Ask anything...", text: $promptText)
                .textFieldStyle(.plain)
                .padding(8)
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 8))
                .focused($isInputFocused)
                .onSubmit {
                    submitTask()
                }
            
            // Quick Actions
            HStack(spacing: 8) {
                ForEach(["Research", "Code", "Browse", "File"], id: \.self) { cat in
                    Button(cat) { selectedCategory = cat }
                        .buttonStyle(.plain)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(
                            selectedCategory == cat 
                                ? AnyShapeStyle(.tint.opacity(0.2))
                                : AnyShapeStyle(.ultraThinMaterial),
                            in: Capsule()
                        )
                        .font(.footnote.weight(.medium))
                }
            }
            
            Divider()
            
            // Results Area
            ScrollView {
                VStack(alignment: .leading, spacing: 8) {
                    if orchestrator.steps.isEmpty {
                        Text("No activity yet.")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                            .padding(.vertical, 4)
                    } else {
                        ForEach(orchestrator.steps.suffix(3)) { step in
                            HStack(alignment: .top, spacing: 6) {
                                stepIcon(for: step.status)
                                    .font(.system(size: 10))
                                Text(step.name)
                                    .font(.caption)
                                    .lineLimit(2)
                                Spacer()
                                if !step.latency.isEmpty {
                                    Text(step.latency)
                                        .font(.system(size: 8))
                                        .foregroundStyle(.tertiary)
                                }
                            }
                        }
                    }
                }
            }
            .frame(maxHeight: 120)
            
            Divider()
            
            // Footer Info
            HStack {
                Text(orchestrator.providerUsed.isEmpty ? "No provider" : orchestrator.providerUsed)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Text(String(format: "Today: $%.2f", NSDecimalNumber(decimal: orchestrator.costToday).doubleValue))
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(16)
        .frame(width: 300)
        .transition(.scale(scale: 0.95).combined(with: .opacity))
        .animation(.spring(duration: 0.2), value: isVisible)
        .onAppear {
            isVisible = true
        }
        .onDisappear {
            isVisible = false
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
        case "failed":
            Image(systemName: "xmark.circle.fill")
                .foregroundColor(.red)
        default:
            Image(systemName: "circle")
                .foregroundColor(.secondary)
        }
    }
    
    @ViewBuilder
    private var statusDot: some View {
        let isWorking = orchestrator.status == .working
        
        if orchestrator.status == .idle {
            Circle()
                .fill(.green)
                .frame(width: 8, height: 8)
                .shadow(color: .green.opacity(0.6), radius: 4)
        } else if isWorking || orchestrator.status == .waiting {
            Image(systemName: isWorking ? "arrow.2.circlepath" : "clock")
                .font(.footnote)
                .foregroundStyle(.yellow)
                .scaleEffect(isWorking ? 1.3 : 1.0)
                .animation(.easeInOut(duration: 0.8).repeatForever(), value: isWorking)
        } else if orchestrator.status == .error {
            Circle()
                .fill(.red)
                .frame(width: 8, height: 8)
                .shadow(color: .red.opacity(0.6), radius: 4)
        } else {
            Circle()
                .fill(.orange)
                .frame(width: 8, height: 8)
        }
    }
    
    private func submitTask() {
        guard !promptText.isEmpty else { return }
        let text = promptText
        promptText = ""
        Task {
            try? await orchestrator.submitTask(prompt: text)
        }
    }
    
    private func openChat() {
        NotificationCenter.default.post(name: NSNotification.Name("OpenChatWindow"), object: nil)
    }
}
