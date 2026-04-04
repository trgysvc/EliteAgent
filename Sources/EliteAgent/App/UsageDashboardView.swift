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
            Section {
                LabeledContent {
                    Text("$\(formattedCost(totalCost))")
                        .font(.title3.weight(.bold).monospaced())
                        .foregroundStyle(.primary)
                } label: {
                    Text("Toplam Harcama")
                        .font(.headline)
                }
            } header: {
                Text("Finansal Özet")
            }
            
            if !metrics.isEmpty {
                Section("Model Bazlı Dağılım") {
                    Chart {
                        ForEach(Array(metrics.keys), id: \.self) { modelID in
                            BarMark(
                                x: .value("Cost", Double(truncating: (metrics[modelID]?.totalCost ?? 0) as NSNumber)),
                                y: .value("Model", modelID.components(separatedBy: "/").last ?? modelID)
                            )
                            .foregroundStyle(by: .value("Model", modelID))
                            .cornerRadius(6)
                        }
                    }
                    .frame(height: 160)
                    .padding(.vertical, 8)
                }
                
                Section("Kullanım Detayları") {
                    ForEach(Array(metrics.keys).sorted(), id: \.self) { modelID in
                        let m = metrics[modelID]!
                        HStack(spacing: 12) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(modelID.components(separatedBy: "/").last ?? modelID)
                                    .font(.subheadline.bold())
                                Text("P: \(m.promptTokens) / C: \(m.completionTokens)")
                                    .font(.caption2.monospacedDigit())
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Text("$\(formattedCost(m.totalCost))")
                                .font(.footnote.monospacedDigit())
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(.secondary.opacity(0.1), in: RoundedRectangle(cornerRadius: 6))
                        }
                        .padding(.vertical, 2)
                    }
                }
            } else {
                ContentUnavailableView {
                    Label("Veri Toplanıyor", systemImage: "chart.bar.fill")
                } description: {
                    Text("Kullanım verileri yapay zeka ile etkileşime geçtikçe burada belirecektir.")
                }
                .frame(minHeight: 200)
            }
            
            Section {
                Button(role: .destructive, action: resetMetrics) {
                    Label("Tüm Verileri Temizle", systemImage: "trash")
                        .frame(maxWidth: .infinity)
                }
            } footer: {
                Text("Bu işlem yapıldıktan sonra maliyet istatistikleri sıfırlanır.")
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
