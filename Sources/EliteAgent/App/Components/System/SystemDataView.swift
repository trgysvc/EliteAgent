import SwiftUI
import EliteAgentCore

struct SystemDataView: View {
    let content: String
    
    // Parse values from [SystemDNA_WIDGET] { ... }
    private var data: SystemData {
        SystemData.parse(from: content)
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Header: Engine Info & Branding
            HStack {
                Image(systemName: "cpu.fill")
                    .font(.title2)
                    .foregroundStyle(.linearGradient(colors: [.blue, .purple], startPoint: .topLeading, endPoint: .bottomTrailing))
                
                VStack(alignment: .leading) {
                    Text("SystemDNA Engine")
                        .font(.headline)
                    Text("Apple Silicon Optimization v20.7")
                        .font(.caption2)
                        .opacity(0.6)
                }
                
                Spacer()
                
                Text("STABLE")
                    .font(.caption2.bold())
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(.green.opacity(0.2))
                    .foregroundStyle(.green)
                    .cornerRadius(4)
            }
            
            Divider().opacity(0.1)
            
            // Core Metrics: RAM & Thermal
            HStack(spacing: 20) {
                // RAM Gauge
                VStack {
                    ZStack {
                        Circle()
                            .stroke(Color.primary.opacity(0.1), lineWidth: 8)
                        Circle()
                            .trim(from: 0, to: CGFloat(data.ramPct) / 100.0)
                            .stroke(ramGradient, style: StrokeStyle(lineWidth: 8, lineCap: .round))
                            .rotationEffect(.degrees(-90))
                            .animation(.spring, value: data.ramPct)
                        
                        VStack {
                            Text("%\(data.ramPct)")
                                .font(.system(.subheadline, design: .rounded).bold())
                            Text("RAM")
                                .font(.system(size: 8).bold())
                                .opacity(0.6)
                        }
                    }
                    .frame(width: 80, height: 80)
                }
                
                VStack(alignment: .leading, spacing: 8) {
                    MetricRow(label: "Kullanılan", value: String(format: "%.1f GB", data.ramUsed), color: .blue)
                    MetricRow(label: "Toplam", value: String(format: "%.1f GB", data.ramTotal), color: .secondary)
                    MetricRow(label: "Termal", value: data.thermalFriendly, color: data.thermalColor)
                }
                
                Spacer()
            }
            
            // Footer: OS & Uptime
            VStack(spacing: 8) {
                HStack {
                    Label(data.os, systemImage: "applelogo")
                    Spacer()
                    Label(data.uptime, systemImage: "clock.fill")
                }
                .font(.caption)
                .opacity(0.8)
                
                HStack {
                    Label(data.cpu, systemImage: "cpu")
                    Spacer()
                    Text("M-Serisi (arm64)")
                }
                .font(.caption2)
                .opacity(0.5)
            }
            .padding(.top, 4)
        }
        .padding(20)
        .background(
            RoundedRectangle(cornerRadius: 24)
                .fill(.ultraThinMaterial)
                .shadow(color: .black.opacity(0.1), radius: 10, x: 0, y: 5)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 24)
                .stroke(Color.primary.opacity(0.1), lineWidth: 1)
        )
    }
    
    private var ramGradient: LinearGradient {
        if data.ramPct > 90 {
            return LinearGradient(colors: [.orange, .red], startPoint: .top, endPoint: .bottom)
        } else if data.ramPct > 75 {
            return LinearGradient(colors: [.yellow, .orange], startPoint: .top, endPoint: .bottom)
        } else {
            return LinearGradient(colors: [.blue, .cyan], startPoint: .top, endPoint: .bottom)
        }
    }
}

// Sub-components
struct MetricRow: View {
    let label: String
    let value: String
    let color: Color
    
    var body: some View {
        HStack {
            Text(label)
                .font(.caption)
                .opacity(0.6)
            Spacer()
            Text(value)
                .font(.caption.bold())
                .foregroundStyle(color)
        }
    }
}

// Data Handling
struct SystemData {
    let os: String
    let thermal: String
    let cpu: String
    let ramTotal: Double
    let ramUsed: Double
    let ramPct: Int
    let uptime: String
    
    var thermalFriendly: String {
        switch thermal {
        case "0": return "Normal"
        case "1": return "Ilık"
        case "2": return "Sıcak"
        case "3": return "Kritik"
        default: return "Stabil"
        }
    }
    
    var thermalColor: Color {
        switch thermal {
        case "0": return .green
        case "1": return .yellow
        case "2": return .orange
        case "3": return .red
        default: return .primary
        }
    }
    
    static func parse(from content: String) -> SystemData {
        let pattern = "\\[SystemDNA_WIDGET\\]\\s*\\{(.*?)\\}"
        guard let regex = try? NSRegularExpression(pattern: pattern, options: []),
              let match = regex.firstMatch(in: content, options: [], range: NSRange(content.startIndex..., in: content)),
              let range = Range(match.range(at: 1), in: content) else {
            return .fallback
        }
        
        let jsonStr = "{\(content[range])}"
        guard let data = jsonStr.data(using: .utf8),
              let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return .fallback
        }
        
        return SystemData(
            os: dict["os"] as? String ?? "macOS",
            thermal: dict["thermal"] as? String ?? "0",
            cpu: dict["cpu"] as? String ?? "Unknown",
            ramTotal: dict["ram_total"] as? Double ?? 16.0,
            ramUsed: dict["ram_used"] as? Double ?? 0.0,
            ramPct: dict["ram_pct"] as? Int ?? 0,
            uptime: dict["uptime"] as? String ?? "0h"
        )
    }
    
    static let fallback = SystemData(os: "macOS", thermal: "0", cpu: "M-Series", ramTotal: 16.0, ramUsed: 8.0, ramPct: 50, uptime: "1h")
}
