import SwiftUI
import EliteAgentCore

/// A macOS-native view for the "Tulpar" Mythology Buddy.
/// Part of the EliteAgent v10.0 "Titan" UI/UX.
public struct TulparView: View {
    @State private var asciiText: String = ""
    @State private var currentStatus: String = "Resting"
    @State private var opacity: Double = 0.8
    
    // Timer for state polling (v10.0: Every 2s)
    let timer = Timer.publish(every: 2, on: .main, in: .common).autoconnect()
    
    public init() {}
    
    public var body: some View {
        VStack(spacing: 12) {
            // ASCII Display
            Text(asciiText)
                .font(.system(.body, design: .monospaced))
                .foregroundColor(.secondary)
                .multilineTextAlignment(.leading)
                .frame(minHeight: 100)
                .transition(.opacity.combined(with: .scale))
            
            // Status Badge
            Text(currentStatus.uppercased())
                .font(.caption2.bold())
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Capsule().fill(Color.accentColor.opacity(0.2)))
                .foregroundColor(.accentColor)
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(.ultraThinMaterial)
                .shadow(color: .black.opacity(0.1), radius: 10, x: 0, y: 5)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(Color.white.opacity(0.1), lineWidth: 1)
        )
        .onReceive(timer) { _ in
            Task {
                let actor = TulparActor.shared
                let state = await actor.getCurrentState()
                let art = await actor.getASCIIArt()
                
                await MainActor.run {
                    withAnimation(.spring()) {
                        self.asciiText = art
                        self.currentStatus = state.rawValue
                    }
                }
            }
        }
        .onAppear {
            Task {
                let art = await TulparActor.shared.getASCIIArt()
                await MainActor.run { self.asciiText = art }
            }
        }
    }
}

#Preview {
    TulparView()
        .preferredColorScheme(.dark)
        .padding()
}
