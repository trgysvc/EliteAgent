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
        Form {
            Section("Maliyet Özeti") {
                LabeledContent {
                    Text("$\(formattedCost(totalCost))")
                        .font(.system(.title3, design: .rounded))
                        .fontWeight(.bold)
                        .foregroundStyle(.green)
                } label: {
                    Text("Toplam Yaşam Boyu Maliyet")
                }
            }
            
            if !metrics.isEmpty {
                Section("Model Dağılımı (Maliyet)") {
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
                    .frame(height: 150)
                    .padding(.vertical, 8)
                }
                
                Section("Kullanım Detayları") {
                    ForEach(Array(metrics.keys).sorted(), id: \.self) { modelID in
                        let m = metrics[modelID]!
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(modelID.components(separatedBy: "/").last ?? modelID)
                                    .font(.headline)
                                Text("P: \(m.promptTokens) / C: \(m.completionTokens)")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Text("$\(formattedCost(m.totalCost))")
                                .font(.system(.body, design: .monospaced))
                                .fontWeight(.medium)
                        }
                        .padding(.vertical, 2)
                    }
                }
            } else {
                Section {
                    ContentUnavailableView {
                        Label("Henüz veri yok", systemImage: "chart.pie")
                    } description: {
                        Text("Yapay zekâ görevleri çalıştırıldığında istatistikler burada görünecektir.")
                    }
                }
            }
            
            Section {
                Button(role: .destructive, action: resetMetrics) {
                    Label("Tüm Verileri Sıfırla", systemImage: "trash")
                        .frame(maxWidth: .infinity)
                }
            } footer: {
                Text("Bu işlem geri alınamaz ve tüm yerel maliyet geçmişini siler.")
            }
        }
        .formStyle(.grouped)
        .navigationTitle("Analizler")
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
