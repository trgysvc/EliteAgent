import SwiftUI
import Charts
import EliteAgentCore

public struct UsageDashboardView: View {
    @ObservedObject var orchestrator: Orchestrator
    @State private var metrics: [String: ModelMetrics] = [:]
    @State private var totalCost: Decimal = 0
    @Environment(\.dismiss) var dismiss
    
    public init(orchestrator: Orchestrator) {
        self.orchestrator = orchestrator
    }
    
    public var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Analytics & Costs")
                    .font(.system(size: 24, weight: .bold, design: .rounded))
                Spacer()
                Button(action: { dismiss() }) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title2)
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
            .padding(24)
            
            ScrollView {
                VStack(spacing: 20) {
                    // Total Cost Card
                    VStack(spacing: 8) {
                        Text("Total Lifetime Cost")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        
                        Text("$\(formattedCost(totalCost))")
                            .font(.system(size: 48, weight: .black, design: .rounded))
                            .foregroundStyle(
                                LinearGradient(colors: [.green, .emerald], startPoint: .top, endPoint: .bottom)
                            )
                    }
                    .frame(maxWidth: .infinity)
                    .padding(32)
                    .background(
                        RoundedRectangle(cornerRadius: 24)
                            .fill(Color(nsColor: .windowBackgroundColor))
                            .shadow(color: .black.opacity(0.1), radius: 10, y: 5)
                            .overlay(
                                RoundedRectangle(cornerRadius: 24)
                                    .stroke(LinearGradient(colors: [.green.opacity(0.3), .clear], startPoint: .topLeading, endPoint: .bottomTrailing), lineWidth: 1)
                            )
                    )
                    
                    if !metrics.isEmpty {
                        // Chart section
                        VStack(alignment: .leading, spacing: 16) {
                            Text("Model Distribution (Cost)")
                                .font(.headline)
                            
                            Chart {
                                ForEach(Array(metrics.keys), id: \.self) { modelID in
                                    BarMark(
                                        x: .value("Cost", Double(truncating: (metrics[modelID]?.totalCost ?? 0) as NSNumber)),
                                        y: .value("Model", modelID.components(separatedBy: "/").last ?? modelID)
                                    )
                                    .foregroundStyle(by: .value("Model", modelID))
                                    .cornerRadius(4)
                                }
                            }
                            .frame(height: 200)
                            .chartLegend(.hidden)
                        }
                        .padding(20)
                        .background(RoundedRectangle(cornerRadius: 20).fill(Color.primary.opacity(0.03)))
                        
                        // Detailed List
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Usage Details")
                                .font(.headline)
                            
                            ForEach(Array(metrics.keys).sorted(), id: \.self) { modelID in
                                let m = metrics[modelID]!
                                HStack {
                                    VStack(alignment: .leading) {
                                        Text(modelID)
                                            .font(.system(.body, design: .monospaced))
                                            .lineLimit(1)
                                        Text("Prompt: \(m.promptTokens) / Completion: \(m.completionTokens)")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                    Text("$\(formattedCost(m.totalCost))")
                                        .font(.headline)
                                }
                                .padding()
                                .background(RoundedRectangle(cornerRadius: 12).fill(Color(nsColor: .controlBackgroundColor)))
                            }
                        }
                    } else {
                        ContentUnavailableView("No usage recorded yet", systemImage: "chart.pie.fill", description: Text("Run a task to see metrics here."))
                            .padding(.top, 40)
                    }
                    
                    Spacer(minLength: 40)
                    
                    Button(role: .destructive, action: resetMetrics) {
                        Label("Reset All Data", systemImage: "trash")
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                    }
                    .buttonStyle(.bordered)
                }
                .padding(24)
            }
        }
        .frame(minWidth: 500, minHeight: 600)
        .onAppear(perform: loadMetrics)
    }
    
    private func loadMetrics() {
        Task {
            let m = await MetricsStore.shared.getMetrics()
            let c = await MetricsStore.shared.getTotalCost()
            await MainActor.run {
                self.metrics = m
                self.totalCost = c
            }
        }
    }
    
    private func resetMetrics() {
        Task {
            await MetricsStore.shared.reset()
            loadMetrics()
        }
    }
    
    private func formattedCost(_ cost: Decimal) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.minimumFractionDigits = 4
        formatter.maximumFractionDigits = 6
        return formatter.string(from: cost as NSNumber) ?? "0.00"
    }
}

extension Color {
    static let emerald = Color(red: 16/255, green: 185/255, blue: 129/255)
}
