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
                        .replacingOccurrences(of: "(?s)\\[WeatherDNA_WIDGET\\].*", with: "", options: .regularExpression, range: nil)
                        .replacingOccurrences(of: "(?s)\\[SystemDNA_WIDGET\\].*", with: "", options: .regularExpression, range: nil)
                        .replacingOccurrences(of: "(?s)\\[MusicDNA_WIDGET\\].*", with: "", options: .regularExpression, range: nil)
                        .replacingOccurrences(of: "(?s)\\[MusicDNA_INFINITY\\].*", with: "", options: .regularExpression, range: nil)
                        .replacingOccurrences(of: "(?s)\\[🖥 Sistem Telemetri Raporu\\].*", with: "", options: .regularExpression, range: nil)
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                    
                    if cleanText.starts(with: "[TASK_COMPLETED]") {
                        let lines = cleanText.components(separatedBy: .newlines)
                        let line1 = lines.indices.contains(1) ? lines[1] : "Task completed."
                        let line2 = lines.indices.contains(2) ? lines[2] : ""
                        
                        VStack(alignment: .leading, spacing: 4) {
                            HStack(spacing: 8) {
                                Image("AppIcon") // EliteAgent Icon
                                    .resizable()
                                    .frame(width: 18, height: 18)
                                    .clipShape(Circle())
                                
                                Text(line1)
                                    .font(.subheadline.bold())
                            }
                            
                            if !line2.isEmpty {
                                Text(line2)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                        .padding(12)
                        .background(Color.secondary.opacity(0.1))
                        .cornerRadius(14)
                    } else if !cleanText.isEmpty {
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
                    
                    if isMusicDNA(message.content) {
                        let fileName = extractFileName(from: message.content)
                        MusicDNAWidgetView(analysis: message.audioAnalysis, fileName: fileName)
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
    
    private func isMusicDNA(_ content: String) -> Bool {
        return content.contains("[MusicDNA_WIDGET]") || content.contains("[MusicDNA_INFINITY]")
    }
    
    private func extractFileName(from content: String) -> String {
        let pattern = "Özet Rapor: (.*)$"
        if let regex = try? NSRegularExpression(pattern: pattern, options: [.anchorsMatchLines]),
           let match = regex.firstMatch(in: content, options: [], range: NSRange(content.startIndex..., in: content)) {
            if let range = Range(match.range(at: 1), in: content) {
                return String(content[range]).trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }
        return "Unknown Track"
    }
}
