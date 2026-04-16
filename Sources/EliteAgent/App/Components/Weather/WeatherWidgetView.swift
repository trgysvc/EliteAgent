import SwiftUI
import WeatherKit

public struct WeatherWidgetView: View {
    private struct WeatherData {
        let location: String
        let status: String?
        let temperature: String?
        let feelsLike: String?
        let highLow: String?
        let humidity: String?
        let wind: String?
        let windGust: String?
        let uvIndex: String?
        let visibility: String?
        let pressure: String?
        let sunrise: String?
        let sunset: String?
        let dewPoint: String?
        let precipitation: String?
    }
    
    private let data: WeatherData
    
    public init(content: String) {
        self.data = WeatherWidgetView.parse(content)
    }
    
    private static func parse(_ raw: String) -> WeatherData {
        func extract(key: String) -> String? {
            let lines = raw.components(separatedBy: .newlines)
            for line in lines {
                if line.contains(key) {
                    if let range = line.range(of: key) {
                        return String(line[range.upperBound...]).trimmingCharacters(in: .whitespaces)
                    }
                }
            }
            return nil
        }
        
        // Helper specifically for combined fields like "Sıcaklık: X | Hissedilen: Y"
        func splitExtract(lineKey: String, partLabel: String) -> String? {
            let lines = raw.components(separatedBy: .newlines)
            guard let line = lines.first(where: { $0.contains(lineKey) }) else { return nil }
            let parts = line.components(separatedBy: "|")
            for part in parts {
                if part.contains(partLabel) {
                    if let range = part.range(of: partLabel) {
                        return String(part[range.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines)
                    }
                }
            }
            return nil
        }

        return WeatherData(
            location: extract(key: "📍")?.components(separatedBy: " - ").first ?? "HAVA DURUMU",
            status: extract(key: "🌤 Durum:"),
            temperature: splitExtract(lineKey: "🌡 Sıcaklık:", partLabel: "🌡 Sıcaklık:"),
            feelsLike: splitExtract(lineKey: "🌡 Sıcaklık:", partLabel: "Hissedilen:"),
            highLow: extract(key: "📈 En Yüksek:"),
            humidity: splitExtract(lineKey: "💧 Nem:", partLabel: "💧 Nem:"),
            wind: splitExtract(lineKey: "💧 Nem:", partLabel: "🌬 Rüzgar:"),
            windGust: splitExtract(lineKey: "🌪 Hamle:", partLabel: "🌪 Hamle:"),
            uvIndex: extract(key: "☀️ UV İndeksi:"),
            visibility: splitExtract(lineKey: "👁 Görüş:", partLabel: "👁 Görüş:"),
            pressure: splitExtract(lineKey: "👁 Görüş:", partLabel: "⏲ Basınç:"),
            sunrise: splitExtract(lineKey: "🌅 Gün Doğumu:", partLabel: "🌅 Gün Doğumu:"),
            sunset: splitExtract(lineKey: "🌅 Gün Doğumu:", partLabel: "🌇 Gün Batımı:"),
            dewPoint: splitExtract(lineKey: "📉 Çiy Noktası:", partLabel: "📉 Çiy Noktası:"),
            precipitation: splitExtract(lineKey: "📉 Çiy Noktası:", partLabel: "🌧 Yağış:")
        )
    }
    
    public var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            headerSection
            Divider().background(Color.primary.opacity(0.1))
            
            mainMetricsSection
            Divider().background(Color.primary.opacity(0.1))
            
            // Premium Grid Layout
            VStack(spacing: 16) {
                HStack(spacing: 12) {
                    WeatherDetailTile(label: "HİSSEDİLEN", value: data.feelsLike ?? "--", icon: "thermometer.medium", color: .orange)
                    WeatherDetailTile(label: "NEM", value: data.humidity ?? "--", icon: "humidity.fill", color: .blue)
                }
                HStack(spacing: 12) {
                    WeatherDetailTile(label: "RÜZGAR", value: data.wind ?? "--", icon: "wind", color: .secondary)
                    WeatherDetailTile(label: "HAMLE", value: data.windGust ?? "--", icon: "wind.snow", color: .teal)
                }
                HStack(spacing: 12) {
                    WeatherDetailTile(label: "UV İNDEKSİ", value: data.uvIndex ?? "--", icon: "sun.max.fill", color: .yellow)
                    WeatherDetailTile(label: "BASINÇ", value: data.pressure ?? "--", icon: "gauge.with.needle.fill", color: .purple)
                }
                HStack(spacing: 12) {
                    WeatherDetailTile(label: "GÖRÜŞ", value: data.visibility ?? "--", icon: "eye.fill", color: .green)
                    WeatherDetailTile(label: "YAĞIŞ", value: data.precipitation ?? "--", icon: "drop.fill", color: .blue)
                }
                HStack(spacing: 12) {
                    WeatherDetailTile(label: "GÜN DOĞUMU", value: data.sunrise ?? "--", icon: "sunrise.fill", color: .orange)
                    WeatherDetailTile(label: "GÜN BATIMI", value: data.sunset ?? "--", icon: "sunset.fill", color: .indigo)
                }
            }
            
            footerSection
        }
        .padding(20)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .stroke(Color.primary.opacity(0.1), lineWidth: 0.5)
        )
        .shadow(color: .black.opacity(0.2), radius: 30, y: 15)
        .frame(maxWidth: 400)
    }
    
    private var headerSection: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(data.location)
                    .font(.system(size: 14, weight: .black))
                    .kerning(1.0)
                    .foregroundStyle(.primary)
                
                if let status = data.status {
                    Text(status)
                        .font(.system(size: 18, weight: .medium))
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            weatherIcon(for: data.status ?? "")
                .font(.system(size: 38))
                .symbolRenderingMode(.multicolor)
                .symbolEffect(.pulse)
        }
    }
    
    private var mainMetricsSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                if let temp = data.temperature {
                    Text(temp)
                        .font(.system(size: 48, weight: .bold, design: .rounded))
                        .foregroundStyle(.primary)
                }
            }
            
            if let highLow = data.highLow {
                Text(highLow)
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(.secondary)
            }
        }
    }
    
    private var footerSection: some View {
        HStack {
            Text("WeatherDNA Engine")
                .font(.system(size: 8, weight: .black))
                .foregroundStyle(.tertiary)
            Spacer()
            if let dew = data.dewPoint {
                Text("Çiy Noktası: \(dew)").font(.system(size: 8)).foregroundStyle(.tertiary)
            }
        }
        .padding(.top, 4)
    }
    
    private func weatherIcon(for condition: String) -> some View {
        let cond = condition.lowercased()
        if cond.contains("bulut") { return Image(systemName: "cloud.fill") }
        if cond.contains("güneş") || cond.contains("açık") { return Image(systemName: "sun.max.fill") }
        if cond.contains("yağmur") { return Image(systemName: "cloud.rain.fill") }
        if cond.contains("kar") { return Image(systemName: "cloud.snow.fill") }
        return Image(systemName: "cloud.sun.fill")
    }
}

struct WeatherDetailTile: View {
    let label: String
    let value: String
    let icon: String
    let color: Color
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(color)
                Text(label)
                    .font(.system(size: 10, weight: .black))
                    .foregroundStyle(.secondary)
            }
            Text(value)
                .font(.system(size: 16, weight: .bold, design: .rounded))
                .foregroundStyle(.primary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(Color.primary.opacity(0.03))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}
