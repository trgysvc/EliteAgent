import SwiftUI
import EliteAgentCore

public struct MenuBarView: View {
    @ObservedObject public var orchestrator: Orchestrator
    @State private var promptText: String = ""
    @State private var selectedCategory: String? = nil
    @State private var isVisible: Bool = false
    @FocusState private var isInputFocused: Bool
    @State private var pulsate: Bool = false
    
    public init(orchestrator: Orchestrator) {
        self.orchestrator = orchestrator
    }
    
    public var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            // Premium Status Header
            HStack {
                statusDot
                    .scaleEffect(pulsate ? 1.2 : 1.0)
                
                Text(orchestrator.status.rawValue.uppercased())
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .tracking(1.2)
                
                Spacer()
                
                Button(action: openChat) {
                    Image(systemName: "uiwindow.split.2x1")
                        .font(.system(size: 12, weight: .semibold))
                }
                .buttonStyle(.plain)
                .help("Open Full Chat (⌘K)")
                .keyboardShortcut("k", modifiers: .command)
            }
            .padding(.bottom, 4)
            
            // Neon Input Field
            ZStack(alignment: .trailing) {
                TextField("COMMAND ACCESS...", text: $promptText)
                    .textFieldStyle(.plain)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .background {
                        RoundedRectangle(cornerRadius: 10)
                            .fill(.ultraThinMaterial)
                            .overlay {
                                RoundedRectangle(cornerRadius: 10)
                                    .stroke(LinearGradient(colors: [.blue.opacity(0.3), .purple.opacity(0.3)], startPoint: .topLeading, endPoint: .bottomTrailing), lineWidth: 1)
                            }
                    }
                    .focused($isInputFocused)
                    .onSubmit {
                        submitTask()
                    }
                
                if !promptText.isEmpty {
                    Image(systemName: "return")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(.blue)
                        .padding(.trailing, 10)
                }
            }
            
            // Tactical Quick Actions
            HStack(spacing: 8) {
                ForEach(["Research", "Code", "Browse", "File"], id: \.self) { cat in
                    Button(cat.uppercased()) { 
                        selectedCategory = (selectedCategory == cat) ? nil : cat 
                    }
                    .buttonStyle(.plain)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(
                        selectedCategory == cat 
                            ? AnyShapeStyle(LinearGradient(colors: [.blue.opacity(0.4), .purple.opacity(0.4)], startPoint: .topLeading, endPoint: .bottomTrailing))
                            : AnyShapeStyle(.ultraThinMaterial.opacity(0.5)),
                        in: RoundedRectangle(cornerRadius: 6)
                    )
                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                    .overlay {
                        if selectedCategory == cat {
                            RoundedRectangle(cornerRadius: 6)
                                .stroke(.blue.opacity(0.5), lineWidth: 1)
                        }
                    }
                }
            }
            
            CustomDivider()
            
            // Real-time Execution Feed
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("ACTIVE FEED")
                        .font(.system(size: 9, weight: .black))
                        .foregroundStyle(.tertiary)
                    Spacer()
                    if orchestrator.status == .working {
                        ProgressView()
                            .scaleEffect(0.4)
                            .frame(width: 12, height: 12)
                    }
                }
                
                ScrollView {
                    VStack(alignment: .leading, spacing: 8) {
                        if orchestrator.steps.isEmpty {
                            Text("AWAITING INITIALIZATION...")
                                .font(.system(size: 10, design: .monospaced))
                                .foregroundStyle(.tertiary)
                                .padding(.vertical, 4)
                        } else {
                            ForEach(orchestrator.steps.suffix(4)) { step in
                                HStack(alignment: .top, spacing: 8) {
                                    stepIcon(for: step.status)
                                        .font(.system(size: 10))
                                        .padding(.top, 2)
                                    
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(step.name.uppercased())
                                            .font(.system(size: 10, weight: .semibold, design: .monospaced))
                                            .lineLimit(1)
                                        
                                        if !step.latency.isEmpty {
                                            Text(step.latency)
                                                .font(.system(size: 8, design: .monospaced))
                                                .foregroundStyle(.tertiary)
                                        }
                                    }
                                }
                                .padding(.vertical, 2)
                            }
                        }
                    }
                }
                .frame(maxHeight: 140)
            }
            
            CustomDivider()
            
            // Cyberpunk Footer
            HStack(alignment: .bottom) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("NODE")
                        .font(.system(size: 8, weight: .black))
                        .foregroundStyle(.tertiary)
                    Text(orchestrator.providerUsed.isEmpty ? "OFFLINE" : orchestrator.providerUsed.uppercased())
                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                        .foregroundStyle(.blue)
                }
                
                Spacer()
                
                VStack(alignment: .trailing, spacing: 2) {
                    Text("DAILY QUOTA")
                        .font(.system(size: 8, weight: .black))
                        .foregroundStyle(.tertiary)
                    Text(String(format: "$%.3f", NSDecimalNumber(decimal: orchestrator.costToday).doubleValue))
                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                        .foregroundStyle(.purple)
                }
            }
        }
        .padding(18)
        .frame(width: 320)
        .background {
            RoundedRectangle(cornerRadius: 20)
                .fill(.background)
                .overlay {
                    RoundedRectangle(cornerRadius: 20)
                        .stroke(LinearGradient(colors: [.white.opacity(0.1), .clear], startPoint: .topLeading, endPoint: .bottomTrailing), lineWidth: 1)
                }
        }
        .onAppear {
            Task { @MainActor in
                withAnimation(.easeInOut(duration: 0.8).repeatForever()) {
                    pulsate = true
                }
            }
        }
    }
    
    @ViewBuilder
    private func stepIcon(for status: String) -> some View {
        switch status {
        case "done":
            Image(systemName: "checkmark.seal.fill")
                .foregroundColor(.green)
        case "running":
            Image(systemName: "rays")
                .foregroundColor(.blue)
        case "failed":
            Image(systemName: "exclamationmark.shield.fill")
                .foregroundColor(.red)
        default:
            Image(systemName: "circle.dotted")
                .foregroundColor(.secondary)
        }
    }
    
    @ViewBuilder
    private var statusDot: some View {
        ZStack {
            Circle()
                .fill(statusColor)
                .frame(width: 8, height: 8)
            
            if orchestrator.status == .working || orchestrator.status == .waiting {
                Circle()
                    .stroke(statusColor.opacity(0.5), lineWidth: 2)
                    .frame(width: 14, height: 14)
                    .scaleEffect(pulsate ? 1.5 : 1.0)
                    .opacity(pulsate ? 0 : 1)
            }
        }
    }
    
    private var statusColor: Color {
        switch orchestrator.status {
        case .idle: return .green
        case .working: return .blue
        case .waiting, .waitingLLM: return .orange
        case .healing: return .purple
        case .error: return .red
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

struct CustomDivider: View {
    var body: some View {
        Rectangle()
            .fill(LinearGradient(colors: [.clear, .white.opacity(0.1), .clear], startPoint: .leading, endPoint: .trailing))
            .frame(height: 1)
            .padding(.vertical, 4)
    }
}
