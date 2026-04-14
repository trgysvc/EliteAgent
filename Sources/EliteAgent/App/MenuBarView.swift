import SwiftUI
import EliteAgentCore
import Combine

/// A high-performance, information-dense macOS MenuBar widget.
/// Strictly adheres to Apple Human Interface Guidelines (HIG).
public struct MenuBarView: View {
    @ObservedObject public var orchestrator: Orchestrator
    @ObservedObject public var modelPickerVM: ModelPickerViewModel
    
    // Internal state for health metrics
    @State private var xpcHealthy: Bool = false
    @State private var thermalState: ProcessInfo.ThermalState = ProcessInfo.processInfo.thermalState
    @State private var llmStatus: String = "IDLE"
    
    // v9.6: Watchdog Integration
    @StateObject private var watchdog = LocalModelWatchdog.shared
    
    // Phase 1: Tool Health State
    @State private var activeToolsCount: Int = 0
    @State private var totalToolsCount: Int = 0
    
    // Performance: Timer managed via State to allow cleanup
    private let healthTimer = Timer.publish(every: 5, on: .main, in: .common).autoconnect()
    
    // Usage Tracking
    @State private var dailyTokens: Int = 0
    @State private var dailyCost: Double = 0.0
    @State private var sessionTokens: Int = 0
    @State private var sessionCost: Double = 0.0
    
    // UI Feedback (Toast)
    @State private var toastMessage: String? = nil
    @State private var showToast: Bool = false
    @State private var isError: Bool = false
    
    public init(orchestrator: Orchestrator, modelPickerVM: ModelPickerViewModel) {
        self.orchestrator = orchestrator
        self.modelPickerVM = modelPickerVM
    }
    
    public var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // SECTION 1: SYSTEM HEALTH (Header)
            healthHeader
            
            Divider()
                .padding(.horizontal, -16) 
            
            // SECTION 2: ACTIVE MODEL (Content)
            activeModelRow
            
            Divider()
                .padding(.horizontal, -16)
            
            // SECTION 3: METRICS & CONTEXT (Progress Bars)
            metricsSection
            
            Divider()
                .padding(.horizontal, -16)
            
            // SECTION 4: QUICK ACTIONS (Footer)
            quickActionsFooter
        }
        .padding(16)
        .frame(width: 320)
        .background(.ultraThinMaterial)
        .onAppear {
            Task {
                await XPCManager.shared.ensureConnected()
                checkXPCHealth()
                updateToolCounts()
            }
            updateUsageStats()
        }
        .onReceive(healthTimer) { _ in
            checkXPCHealth()
            updateLLMStatus()
            updateThermalState()
            updateUsageStats()
            updateToolCounts()
        }
        .overlay(alignment: .bottom) {
            if showToast, let message = toastMessage {
                toastView(message: message)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .padding(.bottom, 68)
            }
        }
    }
    
    @ViewBuilder
    private func toastView(message: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: isError ? "exclamationmark.octagon.fill" : "checkmark.seal.fill")
                .foregroundStyle(isError ? .red : .green)
            Text(message)
                .font(.subheadline.weight(.medium))
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(.ultraThinMaterial, in: Capsule())
    }
    
    // MARK: - Section 1: Health Header
    private var healthHeader: some View {
        VStack(spacing: 8) {
            HStack(spacing: 16) {
                StatusItem(
                    label: "XPC",
                    status: xpcHealthy ? "HEALTHY" : "ERROR",
                    color: xpcHealthy ? .green : .red,
                    icon: "shield.checkered"
                )
                
                Spacer()
                
                StatusItem(
                    label: "LLM",
                    status: watchdog.status.rawValue.uppercased(),
                    color: statusColor,
                    icon: "brain.head.profile"
                )
            }
            
            HStack(spacing: 16) {
                StatusItem(
                    label: "THERMAL",
                    status: thermalLabel,
                    color: thermalColor,
                    icon: "thermometer.medium"
                )
                
                Spacer()
                
                // Detailed Tool Health
                HStack(spacing: 4) {
                    Image(systemName: "hammer.fill")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                    Text("Tools:")
                        .font(.caption2.bold())
                        .foregroundColor(.secondary)
                    Button(action: { openSettingsWindow() }) {
                        Text("\(activeToolsCount)/\(totalToolsCount)")
                            .font(.caption2.monospacedDigit().bold())
                            .foregroundColor(activeToolsCount == totalToolsCount ? .green : .orange)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(.top, 4)
    }
    
    private var activeModelRow: some View {
        HStack(spacing: 12) {
            modelIcon
            VStack(alignment: .leading, spacing: 2) {
                Text(modelPickerVM.selected?.name.uppercased() ?? "MODEL SEÇİNİZ")
                    .font(.subheadline.bold())
                Text(modelLocationLabel)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(.vertical, 4)
    }
    
    private var metricsSection: some View {
        VStack(spacing: 12) {
            MetricProgressView(
                label: "CONTEXT",
                value: Double(sessionTokens),
                total: 200000,
                format: "%d Tokens",
                color: .accentColor
            )
            
            MetricProgressView(
                label: "DAILY BUDGET",
                value: dailyCost,
                total: 5.0,
                format: "$%.2f",
                color: .purple
            )
        }
    }
    
    private var quickActionsFooter: some View {
        HStack(spacing: 8) {
            ActionButton(icon: "arrow.clockwise", label: "Sıfırla") { restartAgent() }
            ActionButton(icon: "cpu", label: "Kurulum") { showModelPicker() }
            ActionButton(icon: "gearshape.fill", label: "Ayarlar") { openSettingsWindow() }
            ActionButton(icon: "message.fill", label: "Sohbet") { openChatWindow() }
        }
        .padding(.top, 4)
    }
    
    private func checkXPCHealth() {
        Task(priority: .background) {
            let isHealthy = await XPCManager.shared.isServiceAvailable()
            await MainActor.run { 
                if self.xpcHealthy != isHealthy {
                    withAnimation { self.xpcHealthy = isHealthy }
                }
            }
        }
    }
    
    private func updateToolCounts() {
        Task {
            let registry = ToolRegistry.shared
            let healthy = registry.getHealthyTools().count
            let total = registry.listTools().count
            await MainActor.run {
                if self.activeToolsCount != healthy || self.totalToolsCount != total {
                    self.activeToolsCount = healthy
                    self.totalToolsCount = total
                }
            }
        }
    }
    
    private func updateLLMStatus() {
        let newStatus = orchestrator.status.displayString.uppercased()
        if llmStatus != newStatus { llmStatus = newStatus }
    }
    
    private func updateThermalState() { thermalState = ProcessInfo.processInfo.thermalState }
    
    private func updateUsageStats() {
        Task(priority: .utility) {
            let stats = await UsageTracker.shared.getStats()
            await MainActor.run {
                self.dailyTokens = stats.dailyTokens
                self.dailyCost = stats.dailyCost
                self.sessionTokens = stats.sessionTokens
                self.sessionCost = stats.sessionCost
            }
        }
    }
    
    private var thermalLabel: String {
        switch thermalState {
        case .nominal: return "NOMINAL"
        case .fair: return "FAIR"
        case .serious: return "HEATING"
        case .critical: return "CRITICAL"
        @unknown default: return "UNKNOWN"
        }
    }
    
    private var thermalColor: Color {
        switch thermalState {
        case .nominal: return .blue
        case .fair: return .green
        case .serious: return .orange
        case .critical: return .red
        @unknown default: return .secondary
        }
    }
    
    private var statusColor: Color {
        guard modelPickerVM.selected != nil else { return .secondary }
        
        switch watchdog.status {
        case .healthy: return .green
        case .degraded: return .orange
        case .critical: return .red
        case .offline: return .red
        }
    }
    
    private var modelIcon: some View {
        Circle()
            .fill(statusColor)
            .frame(width: 10, height: 10)
    }
    
    private var modelLocationLabel: String {
        guard let selected = modelPickerVM.selected else { 
            return "Sistem Hazır Değil" 
        }
        
        let provider = ModelStateManager.shared.activeProvider
        if case .none = provider {
            return "Kurulum Gerekli"
        }
        
        switch selected {
        case .localMLX: return "Local - Titan Engine"
        case .openRouter: return "Cloud - OpenRouter"
        case .custom(_, let name, _, _, _): return name
        }
    }
    
    private func restartAgent() {
        Task {
            try? await XPCManager.shared.restart()
            await InferenceActor.shared.restart()
            triggerToast(message: "Sistem Sıfırlandı", error: false)
        }
    }
    
    private func showModelPicker() {
        NotificationCenter.default.post(name: Notification.Name.openModelSetup, object: nil)
    }
    
    private func openChatWindow() {
        NotificationCenter.default.post(name: Notification.Name.openChat, object: nil)
        NSApp.activate(ignoringOtherApps: true)
    }
    
    private func openSettingsWindow() {
        NotificationCenter.default.post(name: Notification.Name.openSettings, object: nil)
        NSApp.activate(ignoringOtherApps: true)
    }
    
    private func triggerToast(message: String, error: Bool) {
        withAnimation(.spring()) {
            self.toastMessage = message
            self.isError = error
            self.showToast = true
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            withAnimation { self.showToast = false }
        }
    }
}

// MARK: - Subviews
struct StatusItem: View {
    let label: String
    let status: String
    let color: Color
    let icon: String
    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: icon).foregroundStyle(color)
            VStack(alignment: .leading, spacing: 0) {
                Text(label).font(.caption2.bold()).foregroundStyle(.secondary)
                Text(status).font(.footnote.weight(.bold).monospaced()).foregroundStyle(color)
            }
        }
    }
}

struct MetricProgressView: View {
    let label: String
    let value: Double
    let total: Double
    let format: String
    let color: Color
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(label).font(.caption2.bold()).foregroundStyle(.secondary)
                Spacer()
                Text(formatValue()).font(.caption2.monospacedDigit())
            }
            ProgressView(value: min(value, total), total: total).tint(color)
        }
    }
    private func formatValue() -> String {
        format.contains("%d") ? String(format: format, Int(value)) : String(format: format, value)
    }
}

struct ActionButton: View {
    let icon: String
    let label: String
    let action: () -> Void
    @State private var isHovering = false
    var body: some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Image(systemName: icon).font(.title3).foregroundStyle(isHovering ? Color.accentColor : .primary)
                Text(label).font(.caption2).foregroundStyle(isHovering ? .primary : .secondary)
            }
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
    }
}
