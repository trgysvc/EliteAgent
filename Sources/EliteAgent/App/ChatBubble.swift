import SwiftUI
import EliteAgentCore

public struct ChatBubble: View {
    let message: ChatMessage
    @State private var parseError: Bool = false
    
    public init(message: ChatMessage) {
        self.message = message
    }
    
    public var body: some View {
        HStack {
            if message.role == .user { Spacer() }
            
                VStack(alignment: message.role == .user ? .trailing : .leading, spacing: 12) {
                    // 1. Natural Language Text (Conversational Layer)
                    // UNO Pure: All reporting and status info is now pure Markdown.
                    // We remove the raw WeatherDNA block from the text view to keep it clean,
                    // as the widget will handle the rich data display.
                    let cleanText = message.content
                        .replacingOccurrences(of: "\\[WeatherDNA_WIDGET\\].*?\\*(WeatherDNA Engine.*?\\*)", with: "", options: .regularExpression, range: nil)
                        .replacingOccurrences(of: "\\[SystemDNA_WIDGET\\].*?\\}", with: "", options: .regularExpression, range: nil)
                        .replacingOccurrences(of: "(?s)\\[🖥 Sistem Telemetri Raporu\\].*?─────────────────────────────", with: "", options: .regularExpression, range: nil)
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                    
                    if !cleanText.isEmpty {
                        Text(cleanText)
                            .font(.subheadline)
                            .textSelection(.enabled)
                            .padding(12)
                            .background(
                                message.role == .user ? 
                                Color.accentColor : 
                                Color.secondary.opacity(0.1)
                            )
                            .foregroundStyle(message.role == .user ? .white : .primary)
                            .cornerRadius(14)
                    }
                    
                    // 2. Specialized Widgets (UI Layer)
                    // v13.8: Specialized widgets are strictly protocol-delimited (No JSON)
                    if isWeatherDNA(message.content) {
                        WeatherWidgetView(content: message.content)
                            .frame(maxWidth: 400)
                            .transition(.move(edge: .bottom).combined(with: .opacity))
                    }
                    
                    if isSystemDNA(message.content) {
                        SystemDataView(content: message.content)
                            .frame(maxWidth: 400)
                            .transition(.move(edge: .bottom).combined(with: .opacity))
                    }
                }
            
            if message.role == .assistant { Spacer() }
        }
    }
    
    private func isWeatherDNA(_ content: String) -> Bool {
        return content.contains("[WeatherDNA_WIDGET]")
    }
    
    private func isSystemDNA(_ content: String) -> Bool {
        return content.contains("[SystemDNA_WIDGET]")
    }
}
