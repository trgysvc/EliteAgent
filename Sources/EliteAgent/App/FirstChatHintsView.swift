import SwiftUI

/// Educational hints displayed only once for new EliteAgent users.
struct FirstChatHintsView: View {
    @State private var hasSeenHints = UserDefaults.standard.bool(forKey: "hasSeenChatHints")
    
    var body: some View {
        if !hasSeenHints {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Image(systemName: "lightbulb.fill")
                        .foregroundStyle(.orange)
                    Text("Hızlı İpuçları")
                        .font(.headline)
                    Spacer()
                    Button {
                        withAnimation {
                            hasSeenHints = true
                            UserDefaults.standard.set(true, forKey: "hasSeenChatHints")
                        }
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }
                
                VStack(alignment: .leading, spacing: 10) {
                    hintItem(icon: "sparkles", text: "Model değiştirmek için üstteki 'Model Seç' menüsünü kullan.")
                    hintItem(icon: "command", text: "Yeni sohbet başlatmak için ⌘N kısayolunu kullan.")
                    hintItem(icon: "gearshape", text: "Ayarlar ve gizlilik seçenekleri için ⌘, tuşuna bas.")
                }
                
                Button("Anladım") {
                    withAnimation {
                        hasSeenHints = true
                        UserDefaults.standard.set(true, forKey: "hasSeenChatHints")
                    }
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .frame(maxWidth: .infinity, alignment: .trailing)
            }
            .padding(16)
            .frame(width: 300)
            .background(.ultraThinMaterial)
            .cornerRadius(16)
            .overlay(RoundedRectangle(cornerRadius: 16).stroke(.white.opacity(0.1), lineWidth: 1))
            .shadow(color: .black.opacity(0.2), radius: 10, y: 5)
            .padding(20)
            .transition(.move(edge: .top).combined(with: .opacity))
        }
    }
    
    private func hintItem(icon: String, text: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: icon)
                .font(.footnote.bold())
                .foregroundStyle(Color.accentColor)
                .frame(width: 20)
            Text(text)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}
