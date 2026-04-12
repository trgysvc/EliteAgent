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
                    // We remove the raw WeatherDNA block from the text view to keep it clean,
                    // as the widget will handle the rich data display.
                    let cleanText = message.content
                        .replacingOccurrences(of: "\\[WeatherDNA_WIDGET\\].*?\\*(WeatherDNA Engine.*?\\*)", with: "", options: .regularExpression, range: nil)
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
                    if isWeatherDNA(message.content) {
                        WeatherWidgetView(content: message.content)
                            .frame(maxWidth: 400)
                            .transition(.move(edge: .bottom).combined(with: .opacity))
                    }
                    
                    if let report = tryParseReport(message.content) {
                        ResearchReportView(report: report)
                            .frame(maxWidth: 600)
                            .transition(.scale.combined(with: .opacity))
                    }
                }
            
            if message.role == .assistant { Spacer() }
        }
    }
    
    private func isWeatherDNA(_ content: String) -> Bool {
        return content.contains("[WeatherDNA_WIDGET]")
    }
    
    private func tryParseReport(_ content: String) -> ResearchReport? {
        guard UserDefaults.standard.bool(forKey: "enableResearchMode") else { return nil }
        let jsonStr = ThinkParser.extractJSONRobustly(content)
        guard jsonStr.contains("\"report\""), let data = jsonStr.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode(ResearchReport.self, from: data)
    }
}
