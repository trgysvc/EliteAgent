import SwiftUI
import WeatherKit

public struct WeatherWidgetView: View {
    let rawContent: String
    
    public init(content: String) {
        self.rawContent = content
    }
    
    public var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            headerSection
            
            Divider().background(Color.primary.opacity(0.1))
            
            mainMetricsSection
            
            Divider().background(Color.primary.opacity(0.1))
            
            secondaryMetricsSection
            
            footerSection
        }
        .padding(20)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(Color.primary.opacity(0.1), lineWidth: 0.5)
        )
        .shadow(color: .black.opacity(0.15), radius: 20, y: 10)
    }
    
    // MARK: - Subviews
    
    private var headerSection: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(extractValue(for: "📍") ?? "HAVA DURUMU")
                    .font(.headline)
                    .foregroundStyle(.primary)
                
                if let status = extractValue(for: "🌤 Durum:") {
                    Text(status)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            
            weatherIcon(for: extractValue(for: "🌤 Durum:") ?? "")
                .font(.system(size: 32))
                .symbolRenderingMode(.multicolor)
                .symbolEffect(.pulse, options: .repeating)
        }
    }
    
    private var mainMetricsSection: some View {
        HStack(alignment: .firstTextBaseline) {
            if let temp = extractValue(for: "🌡 Sıcaklık:") {
                Text(temp)
                    .font(.system(size: 36, weight: .bold, design: .rounded))
                    .foregroundStyle(.primary)
            }
            
            Spacer()
            
            if let precip = extractValue(for: "🌧 Yağış İhtimali:") {
                Label(precip, systemImage: "drop.fill")
                    .font(.subheadline.bold())
                    .foregroundStyle(.blue)
            }
        }
    }
    
    private var secondaryMetricsSection: some View {
        VStack(spacing: 12) {
            HStack {
                WeatherMetricItem(label: "UV İndeksi", value: extractValue(for: "☀️ UV İndeksi:") ?? "--", icon: "sun.max.fill", color: .orange)
                Spacer()
                WeatherMetricItem(label: "Gün Doğumu", value: extractValue(for: "🌅 Gün Doğumu:") ?? "--", icon: "sunrise.fill", color: .yellow)
            }
            
            HStack {
                WeatherMetricItem(label: "Rüzgar", value: extractValue(for: "💨 Rüzgar:") ?? "--", icon: "wind", color: .secondary)
                Spacer()
                WeatherMetricItem(label: "Gün Batımı", value: extractValue(for: "🌇 Gün Batımı:") ?? "--", icon: "sunset.fill", color: .orange)
            }
        }
    }
    
    private var footerSection: some View {
        HStack {
            if let moon = extractValue(for: "🌙 Ay Safhası:") {
                Label(moon, systemImage: "moon.fill")
                    .font(.caption2.bold())
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Text("WeatherDNA Engine")
                .font(.system(size: 8, weight: .black))
                .foregroundStyle(.tertiary)
        }
    }
    
    // MARK: - Helpers
    
    private func extractValue(for key: String) -> String? {
        let lines = rawContent.components(separatedBy: .newlines)
        for line in lines {
            if line.contains(key) {
                return line.replacingOccurrences(of: key, with: "").trimmingCharacters(in: .whitespaces)
            }
            // Handle specific header format 📍 ANKARA - ŞİMDİ
            if key == "📍" && line.starts(with: "📍") {
                return line.replacingOccurrences(of: "📍", with: "").trimmingCharacters(in: .whitespaces)
            }
        }
        return nil
    }
    
    private func weatherIcon(for condition: String) -> some View {
        let cond = condition.lowercased()
        if cond.contains("bulut") { return Image(systemName: "cloud.fill") }
        if cond.contains("güneş") || cond.contains("açık") { return Image(systemName: "sun.max.fill") }
        if cond.contains("yağmur") { return Image(systemName: "cloud.rain.fill") }
        if cond.contains("kar") { return Image(systemName: "cloud.snow.fill") }
        if cond.contains("fırtına") { return Image(systemName: "cloud.bolt.fill") }
        return Image(systemName: "cloud.sun.fill")
    }
}

struct WeatherMetricItem: View {
    let label: String
    let value: String
    let icon: String
    let color: Color
    
    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .foregroundStyle(color)
            VStack(alignment: .leading) {
                Text(label).font(.caption2).foregroundStyle(.secondary)
                Text(value).font(.caption.bold()).foregroundStyle(.primary)
            }
        }
    }
}

#Preview {
    WeatherWidgetView(content: """
    📍 ANKARA - BUGÜN 🌦
    ───────────────────────────
    🌤 Durum: Parçalı Bulutlu
    🌡 Sıcaklık: En Yüksek 18°C | En Düşük 9°C
    ───────────────────────────
    ☀️ UV İndeksi: 4 (Orta)
    🌧 Yağış İhtimali: %12
    🌅 Gün Doğumu: 05:12 | 🌇 Gün Batımı: 18:09
    🌙 Ay Safhası: İlk Dördün
    ───────────────────────────
    *(WeatherDNA Engine v14.10)*
    """)
    .frame(width: 350)
    .padding()
}
