import SwiftUI
import Foundation
import EliteAgentCore

public struct WeatherData: Sendable {
    public var condition: String = "Mostly Sunny"
    public var high: String = "--"
    public var low: String = "--"
    public var hissedilen: String = "--"
    public var nem: String = "--"
    public var ruzgar: String = "--"
    public var hamle: String = "--"
    public var uvIndex: String = "--"
    public var basinc: String = "--"
    public var gorus: String = "--"
    public var yagis: String = "--"
    public var gunDogumu: String = "--"
    public var gunBatimi: String = "--"
    
    public init() {}
}

public struct WeatherWidgetView: View {
    private let content: String
    private let data: WeatherData
    
    public init(content: String) {
        self.content = content
        self.data = WeatherWidgetView.parse(content: content)
    }
    
    static func parse(content: String) -> WeatherData {
        var data = WeatherData()
        let scanner = Scanner(string: content)
        scanner.charactersToBeSkipped = .whitespacesAndNewlines
        
        func extract(for key: String) -> String? {
            let s = Scanner(string: content)
            while !s.isAtEnd {
                if s.scanString(key) != nil {
                    if let val = s.scanUpToCharacters(from: .newlines) {
                        return val.trimmingCharacters(in: .whitespaces)
                            .replacingOccurrences(of: ":", with: "")
                            .trimmingCharacters(in: .whitespaces)
                    }
                }
                // String olmayan karakterleri güvenli bir şekilde atla
                if s.isAtEnd { break }
                _ = s.scanCharacter()
            }
            return nil
        }
        
        data.condition = extract(for: "[DURUM]") ?? "Mostly Sunny"
        data.high = extract(for: "[YUKSEK]") ?? "--"
        data.low = extract(for: "[DUSUK]") ?? "--"
        data.hissedilen = extract(for: "[HIS]") ?? "--"
        data.nem = extract(for: "[NEM]") ?? "--"
        data.ruzgar = extract(for: "[RUZGAR]") ?? "--"
        data.hamle = extract(for: "[HAMLE]") ?? "--"
        data.uvIndex = extract(for: "[UV]") ?? "--"
        data.basinc = extract(for: "[PRES]") ?? "--"
        data.gorus = extract(for: "[GORUS]") ?? "--"
        data.yagis = extract(for: "[YAGIS]") ?? "--"
        data.gunDogumu = extract(for: "[DOGUM]") ?? "--"
        data.gunBatimi = extract(for: "[BATIM]") ?? "--"
        
        return data
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack {
                Text("WEATHER")
                    .font(.system(size: 20, weight: .black))
                    .foregroundColor(.white)
                    .tracking(1)
                
                Spacer()
                
                Image(systemName: "cloud.sun.fill")
                    .renderingMode(.original)
                    .font(.system(size: 44))
                    .shadow(color: .yellow.opacity(0.3), radius: 10)
            }
            .padding(.top, 10)
            
            Divider()
                .background(Color.white.opacity(0.1))
            
            VStack(spacing: 12) {
                HStack(spacing: 12) {
                    InfoTile(label: "HISSEDILEN", value: data.hissedilen, icon: "thermometer.medium", iconColor: .orange)
                    InfoTile(label: "NEM", value: data.nem, icon: "drop.fill", iconColor: .blue)
                }
                HStack(spacing: 12) {
                    InfoTile(label: "RUZGAR", value: data.ruzgar, icon: "wind", iconColor: .gray)
                    InfoTile(label: "HAMLE", value: data.hamle, icon: "wind", iconColor: .cyan)
                }
                HStack(spacing: 12) {
                    InfoTile(label: "UV INDEKSI", value: data.uvIndex, icon: "sun.max.fill", iconColor: .yellow)
                    InfoTile(label: "BASINC", value: data.basinc, icon: "circle.fill", iconColor: .purple)
                }
                HStack(spacing: 12) {
                    InfoTile(label: "GORUS", value: data.gorus, icon: "eye.fill", iconColor: .green)
                    InfoTile(label: "YAGIS", value: data.yagis, icon: "drop.fill", iconColor: .blue)
                }
                HStack(spacing: 12) {
                    InfoTile(label: "GUN DOGUMU", value: data.gunDogumu, icon: "sunrise.fill", iconColor: .orange)
                    InfoTile(label: "GUN BATIMI", value: data.gunBatimi, icon: "sunset.fill", iconColor: .purple)
                }
            }
            
            Text("WeatherDNA v14.15 Final Engine")
                .font(.system(size: 11, weight: .bold, design: .monospaced))
                .foregroundColor(.white.opacity(0.3))
                .padding(.top, 10)
        }
        .padding(25)
        .background(
            RoundedRectangle(cornerRadius: 32)
                .fill(Color(red: 31/255, green: 33/255, blue: 46/255))
                .shadow(color: .black.opacity(0.4), radius: 20, x: 0, y: 15)
        )
        .padding(.horizontal)
    }
}

struct InfoTile: View {
    let label: String
    let value: String
    let icon: String
    let iconColor: Color
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 12, weight: .bold))
                    .foregroundColor(iconColor)
                
                Text(label)
                    .font(.system(size: 11, weight: .black))
                    .foregroundColor(.white.opacity(0.6))
                    .tracking(0.5)
            }
            
            Text(value)
                .font(.system(size: 20, weight: .bold))
                .foregroundColor(.white)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(Color.white.opacity(0.05))
        .cornerRadius(18)
    }
}
