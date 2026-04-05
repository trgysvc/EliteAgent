import SwiftUI
import Charts
import EliteAgentCore

public struct LLMHealthDashboardView: View {
    @StateObject private var watchdog = LocalModelWatchdog.shared
    @State private var showingExportSheet = false
    @State private var exportedURL: URL? = nil
    
    public init() {}
    
    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                headerSection
                
                if watchdog.history.isEmpty {
                    ContentUnavailableView("Veri Yok", systemImage: "chart.bar.xaxis", description: Text("Metrik toplama devrede, ilk veri noktaları bekleniyor..."))
                        .frame(height: 300)
                } else {
                    vramChartSection
                    performanceChartSection
                    eventJournalSection
                }
                
                exportSection
            }
            .padding(24)
        }
        .navigationTitle("Sistem Sağlığı")
    }
    
    private var headerSection: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text("📊 Model Sağlığı & Performans")
                    .font(.title2.bold())
                Text("Gerçek zamanlı çıkarım (inference) ve kaynak kullanımı analizi.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            
            HealthStatusBadge() // Reuse the badge from ChatWindowView
        }
    }
    
    private var vramChartSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Bellek Kullanımı (VRAM)", systemImage: "memorychip")
                .font(.headline)
            
            Chart(watchdog.history) { sample in
                AreaMark(
                    x: .value("Zaman", sample.timestamp),
                    y: .value("Kullanım %", sample.vramUsage * 100)
                )
                .foregroundStyle(
                    .linearGradient(
                        colors: [vramColor(sample.vramUsage).opacity(0.5), vramColor(sample.vramUsage).opacity(0.1)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                
                LineMark(
                    x: .value("Zaman", sample.timestamp),
                    y: .value("Kullanım %", sample.vramUsage * 100)
                )
                .foregroundStyle(vramColor(sample.vramUsage))
                .symbol(.circle)
            }
            .frame(height: 180)
            .chartYScale(domain: 0...100)
            .chartXAxis {
                AxisMarks(values: .stride(by: .minute)) { _ in
                    AxisValueLabel(format: .dateTime.hour().minute())
                }
            }
        }
        .padding()
        .background(.primary.opacity(0.03), in: RoundedRectangle(cornerRadius: 16))
    }
    
    private var performanceChartSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Performans (Tokens/sn)", systemImage: "bolt.fill")
                .font(.headline)
            
            Chart(watchdog.history) { sample in
                BarMark(
                    x: .value("Zaman", sample.timestamp),
                    y: .value("TPS", sample.tokensPerSec)
                )
                .foregroundStyle(sample.tokensPerSec < 10 ? .orange : .green)
                .cornerRadius(4)
            }
            .frame(height: 180)
            .chartYScale(domain: 0...100)
        }
        .padding()
        .background(.primary.opacity(0.03), in: RoundedRectangle(cornerRadius: 16))
    }
    
    private var eventJournalSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Olay Günlüğü", systemImage: "list.bullet.indent")
                .font(.headline)
            
            let recoveryEvents = watchdog.history.filter { $0.status != .healthy }
            
            if recoveryEvents.isEmpty {
                Text("Hiçbir kritik olay saptanmadı. Sistem stabil.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 8)
            } else {
                VStack(spacing: 8) {
                    ForEach(recoveryEvents.suffix(5).reversed()) { event in
                        HStack {
                            Text(event.timestamp, style: .time)
                                .font(.caption.monospaced())
                            Text("→")
                            Text(event.status.rawValue)
                                .font(.caption.bold())
                                .foregroundStyle(statusColor(event.status))
                            Spacer()
                            Text("Otomatik Kurtarma Tetiklendi")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                        .padding(8)
                        .background(.primary.opacity(0.02), in: RoundedRectangle(cornerRadius: 8))
                    }
                }
            }
        }
        .padding()
        .background(.primary.opacity(0.03), in: RoundedRectangle(cornerRadius: 16))
    }
    
    private var exportSection: some View {
        Button {
            exportedURL = watchdog.exportMetrics()
            if exportedURL != nil { showingExportSheet = true }
        } label: {
            Label("📤 Metrikleri JSON Olarak Dışa Aktar", systemImage: "square.and.arrow.up")
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.bordered)
        .controlSize(.large)
        .fileExporter(isPresented: $showingExportSheet, document: JSONDocument(url: exportedURL), contentType: .json) { result in
            // Handle success/failure
        }
    }
    
    private func vramColor(_ usage: Float) -> Color {
        if usage > 0.9 { return .red }
        if usage > 0.75 { return .orange }
        return .blue
    }
    
    private func statusColor(_ status: ModelHealthStatus) -> Color {
        switch status {
        case .healthy: return .green
        case .degraded: return .orange
        case .critical: return .red
        }
    }
}

// Minimal JSON Document Wrapper for FileExporter
struct JSONDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.json] }
    var url: URL?
    
    init(url: URL?) { self.url = url }
    
    init(configuration: ReadConfiguration) throws { self.url = nil }
    
    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        guard let url = url, let data = try? Data(contentsOf: url) else {
            throw CocoaError(.fileReadUnknown)
        }
        return FileWrapper(regularFileWithContents: data)
    }
}
import UniformTypeIdentifiers
