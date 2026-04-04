import SwiftUI
import EliteAgentCore

/// An expandable timeline visualization for agent process steps.
public struct AgentProcessTimeline: View {
    let currentStep: ProcessStep
    @State private var isExpanded = true
    
    public init(currentStep: ProcessStep) {
        self.currentStep = currentStep
    }
    
    public var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                    isExpanded.toggle()
                }
            } label: {
                HStack(spacing: 12) {
                    StepBadge(status: currentStep.status, icon: currentStep.icon)
                    
                    VStack(alignment: .leading, spacing: 4) {
                        Text(currentStep.name)
                            .font(.headline)
                        
                        Text(statusDescription)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    
                    Spacer()
                    
                    Image(systemName: "chevron.right")
                        .font(.caption.bold())
                        .foregroundStyle(.secondary)
                        .rotationEffect(.degrees(isExpanded ? 90 : 0))
                }
                .padding(16)
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("İşlem adımı: \(currentStep.name)")
            .accessibilityHint(isExpanded ? "Detayları gizlemek için dokunun" : "Detayları görmek için dokunun")
            
            if isExpanded {
                VStack(alignment: .leading, spacing: 12) {
                    // Logic to show past steps could be added if we store them in a history list.
                    // For now, we show the active "Processing" phase steps as illustrative.
                    
                    TimelineItem(name: "📂 File Received", status: .success, isFirst: true)
                    TimelineItem(name: "🔍 Extraction", status: currentStep.name.contains("Extraction") ? .active : (currentStep.name.contains("Reasoning") || currentStep.name.contains("Generation") ? .success : .pending))
                    TimelineItem(name: "🧠 Reasoning", status: currentStep.name.contains("Reasoning") ? .active : (currentStep.name.contains("Generation") ? .success : .pending))
                    TimelineItem(name: "✍️ Generation", status: currentStep.name.contains("Generation") ? .active : .pending, isLast: true)
                }
                .padding(.leading, 32)
                .padding(.top, 16)
                .padding(.bottom, 16)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .padding(.horizontal)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Agent İşlem Durumu: \(currentStep.name)")
        .accessibilityValue(statusDescription)
    }
    
    private var statusDescription: String {
        switch currentStep.status {
        case .pending: return "Beklemede..."
        case .active: return "İşlem yapılıyor..."
        case .success: return "Tamamlandı"
        case .error: return "Hata oluştu"
        }
    }
}

private struct StepBadge: View {
    let status: ProcessStep.Status
    let icon: String
    
    var body: some View {
        ZStack {
            Circle()
                .fill(statusColor.opacity(0.15))
                .frame(width: 32, height: 32)
            
            Image(systemName: status == .active ? icon : (status == .success ? "checkmark" : (status == .error ? "exclamationmark" : icon)))
                .font(.subheadline.bold())
                .foregroundStyle(statusColor)
                .symbolEffect(.pulse, options: .repeating, isActive: status == .active)
        }
    }
    
    private var statusColor: Color {
        switch status {
        case .pending: return .secondary
        case .active: return .accentColor
        case .success: return .green
        case .error: return .red
        }
    }
}

private struct TimelineItem: View {
    let name: String
    let status: ProcessStep.Status
    var isFirst: Bool = false
    var isLast: Bool = false
    
    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                // Connecting terminal lines
                VStack(spacing: 0) {
                    Rectangle()
                        .fill(isFirst ? Color.clear : Color.primary.opacity(0.1))
                        .frame(width: 2, height: 10)
                    
                    Circle()
                        .fill(statusColor)
                        .frame(width: 8, height: 8)
                    
                    Rectangle()
                        .fill(isLast ? Color.clear : Color.primary.opacity(0.1))
                        .frame(width: 2, height: 10)
                }
                
                if status == .active {
                    Circle()
                        .stroke(statusColor.opacity(0.3), lineWidth: 4)
                        .frame(width: 14, height: 14)
                        .scaleEffect(1.2)
                        .opacity(0.6)
                        .symbolEffect(.pulse)
                }
            }
            
            Text(name)
                .font(.subheadline)
                .foregroundStyle(status == .pending ? .secondary : .primary)
                .strikethrough(status == .success, color: .green.opacity(0.3))
            
            Spacer()
            
            if status == .active {
                ProgressView()
                    .controlSize(.small)
                    .tint(.accentColor)
            }
        }
    }
    
    private var statusColor: Color {
        switch status {
        case .pending: return .secondary.opacity(0.3)
        case .active: return .accentColor
        case .success: return .green
        case .error: return .red
        }
    }
}

#Preview {
    VStack {
        AgentProcessTimeline(currentStep: .step(name: "Reasoning & Context Prep", status: .active, icon: "brain.headset"))
    }
    .background(Color.black)
}
