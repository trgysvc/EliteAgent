import SwiftUI
import AudioIntelligenceCore

public struct MusicDNAWidgetView: View {
    let analysis: MusicDNAAnalysis?
    let fileName: String
    
    public init(analysis: MusicDNAAnalysis?, fileName: String = "Unknown Track") {
        self.analysis = analysis
        self.fileName = fileName
    }
    
    public var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            headerSection
            
            // Bento Grid: Main Metrics
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                metricCard(title: "TEMPO", value: String(format: "%.1f BPM", analysis?.rhythm.bpm ?? 0), subValue: "Largo - Adagio", icon: "metronome.fill", color: .orange)
                
                metricCard(title: "LOUDNESS", value: String(format: "%.1f LUFS", analysis?.mastering.integratedLUFS ?? 0), subValue: "Dinamik Aralık: Orta", icon: "speaker.wave.3.fill", color: .blue)
                
                metricCard(title: "DOMINANT", value: analysis?.tonality.key ?? "A#", subValue: "G min / Bb maj", icon: "music.note", color: .purple)
                
                metricCard(title: "H/P ORAN", value: String(format: "%.2f", (analysis?.hpss.harmonicEnergyRatio ?? 1) / max(0.01, analysis?.hpss.percussiveEnergyRatio ?? 1)), subValue: "Harmonik Ağırlık", icon: "waveform.path.ecg", color: .green)
            }
            
            // Visual DNA: Chromagram & Spectral Contrast
            VStack(spacing: 12) {
                SectionHeader(title: "TONAL FLOW (12-NOTE CHROMAGRAM)")
                chromagramBar
                
                SectionHeader(title: "SPECTRAL CONTRAST (7 BANDS)")
                spectralContrastBar
            }
            
            // Action Bar: The 3 Options
            HStack(spacing: 10) {
                DNAActionButton(title: "Adli Denetim", icon: "magnifyingglass.circle.fill")
                DNAActionButton(title: "Müzikolojik Denetim", icon: "music.quarternote.beam")
                DNAActionButton(title: "Kapsamlı Rapor", icon: "doc.text.below.ecg.fill")
            }
        }
        .padding(24)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 32, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 32, style: .continuous)
                .stroke(Color.primary.opacity(0.1), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.2), radius: 30, x: 0, y: 15)
        .frame(maxWidth: 450)
    }
    
    // MARK: - Components
    
    private var headerSection: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(fileName)
                    .font(.system(size: 20, weight: .bold, design: .rounded))
                Text("Music DNA Infinity v8.1.5")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.secondary)
            }
            Spacer()
            
            ForensicShield(isNative: !(analysis?.forensic.isUpsampled ?? false))
        }
    }
    
    private func metricCard(title: String, value: String, subValue: String, icon: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: icon)
                    .foregroundStyle(color)
                    .font(.system(size: 14, weight: .bold))
                Text(title)
                    .font(.system(size: 10, weight: .black))
                    .foregroundStyle(.tertiary)
            }
            
            VStack(alignment: .leading, spacing: 2) {
                Text(value)
                    .font(.system(size: 18, weight: .bold, design: .rounded))
                Text(subValue)
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.primary.opacity(0.03))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
    
    private var chromagramBar: some View {
        HStack(spacing: 2) {
            let colors: [Color] = [.blue, .cyan, .teal, .green, .yellow, .orange, .red, .pink, .purple, .indigo, .blue, .cyan]
            ForEach(0..<12) { i in
                RoundedRectangle(cornerRadius: 3)
                    .fill(colors[i % colors.count].opacity(0.8))
                    .frame(height: 18)
            }
        }
        .padding(4)
        .background(Color.black.opacity(0.2))
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }
    
    private var spectralContrastBar: some View {
        HStack(spacing: 3) {
            ForEach(0..<7) { _ in
                RoundedRectangle(cornerRadius: 2)
                    .fill(LinearGradient(colors: [.blue.opacity(0.8), .purple.opacity(0.4)], startPoint: .top, endPoint: .bottom))
                    .frame(maxWidth: .infinity)
                    .frame(height: 24)
            }
        }
    }
}

// MARK: - Supporting Views

struct SectionHeader: View {
    let title: String
    var body: some View {
        Text(title)
            .font(.system(size: 9, weight: .black))
            .foregroundStyle(.tertiary)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct ForensicShield: View {
    let isNative: Bool
    var body: some View {
        VStack(alignment: .trailing, spacing: 2) {
            Text("Orijinallik")
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(.secondary)
            Image(systemName: isNative ? "checkmark.shield.fill" : "exclamationmark.shield.fill")
                .font(.system(size: 28))
                .foregroundStyle(isNative ? .green : .red)
                .symbolEffect(.bounce, value: isNative)
        }
    }
}

struct DNAActionButton: View {
    let title: String
    let icon: String
    
    var body: some View {
        Button(action: {}) {
            VStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 18))
                Text(title)
                    .font(.system(size: 9, weight: .bold))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background(Color.primary.opacity(0.05))
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}


#Preview {
    ZStack {
        Color.black.ignoresSafeArea()
        MusicDNAWidgetView(analysis: nil, fileName: "Bohemian Rhapsody")
            .padding()
    }
}
