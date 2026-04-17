import SwiftUI

public struct MusicDNAWidgetView: View {
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
            
            pitchAndVocalSection
            
            Divider().background(Color.primary.opacity(0.1))
            
            hpssSection
            
            Divider().background(Color.primary.opacity(0.1))
            
            spectralContrastSection
            
            Divider().background(Color.primary.opacity(0.1))
            
            chromaMapSection
            
            Divider().background(Color.primary.opacity(0.1))
            
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
                Text(extractValue(for: "# ✨ Elite Music DNA Infinity Audit:") ?? "AUDIO ANALYSIS")
                    .font(.headline)
                    .foregroundStyle(.primary)
                
                Text(extractKey(for: "Key Detection:") ?? "--")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            
            let isUpsampled = rawContent.contains("⚠️ FAKE HI-RES")
            VStack(alignment: .trailing, spacing: 4) {
                Image(systemName: isUpsampled ? "Exclamationmark.shield.fill" : "checkmark.shield.fill")
                    .font(.system(size: 24))
                    .foregroundStyle(isUpsampled ? .red : .green)
                Text(isUpsampled ? "UPSAMPLED" : "NATIVE")
                    .font(.system(size: 8, weight: .black))
                    .foregroundStyle(isUpsampled ? .red : .green)
            }
        }
    }
    
    private var mainMetricsSection: some View {
        VStack(spacing: 12) {
            HStack {
                MusicMetricItem(label: "TEMPO", value: extractValue(for: "- **Master BPM**:") ?? "--", icon: "metronome.fill", color: .orange)
                Spacer()
                MusicMetricItem(label: "LOUDNESS", value: extractValue(for: "**Integrated LUFS** |") ?? "--", icon: "speaker.wave.3.fill", color: .blue)
            }
            
            HStack {
                MusicMetricItem(label: "DYNAMIC RANGE", value: extractValue(for: "- **Dynamic Range**:") ?? "--", icon: "arrow.up.and.down.and.sparkles", color: .green)
                Spacer()
                MusicMetricItem(label: "TRUE PEAK", value: extractValue(for: "**True Peak** |") ?? "--", icon: "barometer", color: .red)
            }
        }
    }
    
    private var pitchAndVocalSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("PITCH & VOCAL DNA")
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(.tertiary)
            
            HStack {
                VStack(alignment: .leading) {
                    Text("Mean F0").font(.system(size: 8)).foregroundStyle(.secondary)
                    Text(extractValue(for: "- **Mean Fundamental (F0)**:") ?? "--").font(.caption.bold())
                }
                Spacer()
                VStack(alignment: .leading) {
                    Text("Stability").font(.system(size: 8)).foregroundStyle(.secondary)
                    Text(extractValue(for: "- **Pitch Stability**:") ?? "--").font(.caption.bold())
                }
                Spacer()
                VStack(alignment: .leading) {
                    Text("Voice Ratio").font(.system(size: 8)).foregroundStyle(.secondary)
                    Text(extractValue(for: "- **Voiced Ratio**:") ?? "--").font(.caption.bold())
                }
            }
        }
    }
    
    private var spectralContrastSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("SPECTRAL CONTRAST (7 BANDS)")
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(.tertiary)
            
            HStack(alignment: .bottom, spacing: 4) {
                ForEach(0..<7) { i in
                    let val = extractBarValue(for: "- Band \(i):")
                    VStack(spacing: 4) {
                        RoundedRectangle(cornerRadius: 2)
                            .fill(LinearGradient(colors: [.blue.opacity(0.8), .cyan.opacity(0.5)], startPoint: .top, endPoint: .bottom))
                            .frame(width: 30, height: CGFloat(val * 40))
                        Text("B\(i)").font(.system(size: 6)).foregroundStyle(.tertiary)
                    }
                }
            }
            .frame(height: 50)
        }
    }
    
    private var chromaMapSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("CHROMAGRAM (TONAL MAP)")
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(.tertiary)
            
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 2) {
                    let notes = ["C", "C#", "D", "D#", "E", "F", "F#", "G", "G#", "A", "A#", "B"]
                    ForEach(notes, id: \.self) { note in
                        let val = extractBarValue(for: "- **\(note.padding(toLength: 3, withPad: " ", startingAt: 0))**:")
                        VStack(spacing: 2) {
                            RoundedRectangle(cornerRadius: 1)
                                .fill(val > 0.7 ? Color.purple : Color.purple.opacity(0.3))
                                .frame(width: 24, height: CGFloat(20 + (val * 40)))
                            Text(note).font(.system(size: 7, weight: .bold)).foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
    }
    
    private var hpssSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("HPSS BALANCE")
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(.tertiary)
            
            HStack(spacing: 4) {
                let hRatio = extractNumeric(for: "- **Harmonic**:") ?? 0.5
                let pRatio = extractNumeric(for: "- **Percussive**:") ?? 0.5
                
                GeometryReader { geo in
                    HStack(spacing: 0) {
                        Rectangle()
                            .fill(LinearGradient(colors: [.purple, .blue], startPoint: .leading, endPoint: .trailing))
                            .frame(width: geo.size.width * CGFloat(hRatio))
                        
                        Rectangle()
                            .fill(LinearGradient(colors: [.orange, .red], startPoint: .leading, endPoint: .trailing))
                            .frame(width: geo.size.width * CGFloat(pRatio))
                    }
                }
                .frame(height: 8)
                .clipShape(Capsule())
            }
            .frame(height: 8)
            
            HStack {
                Text("Harmonic (\(Int((extractNumeric(for: "- **Harmonic**:") ?? 0) * 100))%)")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Spacer()
                Text("Percussive (\(Int((extractNumeric(for: "- **Percussive**:") ?? 0) * 100))%)")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
    }
    
    private var footerSection: some View {
        HStack {
            Text(extractValue(for: "**Bit-Depth Integrity** |") ?? "Native Bit-Depth")
                .font(.caption2.bold())
                .foregroundStyle(.secondary)
            Spacer()
            Text("Infinity Engine v41.1")
                .font(.system(size: 8, weight: .black))
                .foregroundStyle(.tertiary)
        }
    }
    
    // MARK: - Helpers
    
    private func extractValue(for key: String) -> String? {
        let lines = rawContent.components(separatedBy: .newlines)
        for line in lines {
            if line.contains(key) {
                var value = line.replacingOccurrences(of: key, with: "")
                value = value.replacingOccurrences(of: "**", with: "")
                value = value.replacingOccurrences(of: "|", with: "")
                value = value.components(separatedBy: "(").first ?? value
                return value.trimmingCharacters(in: .whitespaces)
            }
        }
        return nil
    }
    
    private func extractKey(for label: String) -> String? {
        let lines = rawContent.components(separatedBy: .newlines)
        for line in lines {
            if line.contains(label) {
                return line.components(separatedBy: ":").last?.trimmingCharacters(in: .whitespaces)
            }
        }
        return nil
    }
    
    private func extractNumeric(for key: String) -> Double? {
        if let val = extractValue(for: key) {
            let numericString = val.filter { "0123456789.".contains($0) }
            if let d = Double(numericString) {
                return d > 1 ? d / 100.0 : d
            }
        }
        return nil
    }

    private func extractBarValue(for key: String) -> Double {
        let lines = rawContent.components(separatedBy: .newlines)
        for line in lines {
            if line.contains(key) {
                // Look for the block characters and count them
                let blocks = line.filter { $0 == "█" }.count
                return Double(blocks) / 20.0 // Normalize to 0-1 range based on template (20 chars for spectral, 25 for chroma)
            }
        }
        return 0.1
    }
}


struct MusicMetricItem: View {
    let label: String
    let value: String
    let icon: String
    let color: Color
    
    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .foregroundStyle(color)
                .frame(width: 20)
            VStack(alignment: .leading) {
                Text(label).font(.system(size: 8, weight: .bold)).foregroundStyle(.secondary)
                Text(value).font(.caption.bold()).foregroundStyle(.primary)
            }
        }
    }
}

#Preview {
    MusicDNAWidgetView(content: """
    # 🧬 Elite Music DNA Audit: test.mp3
    ## 🎚️ 1. Mastering Engineer Dashboard
    | Metric | Value | Compliance / Status |
    | :--- | :--- | :--- |
    | **Integrated LUFS** | -14.20 LUFS | High |
    | **True Peak** | -0.12 dBTP | ✅ Safe |
    
    ## 🥁 2. Ritim & Tempo DNA
    - **BPM**: 124.00
    - **Beat Consistency**: 0.0120s (Hassas Grid)
    
    ## 🧪 3. Spektrum & Timbre (Infinity Audit)
    - **Dynamic Range**: 12.5 dB
    
    ### HPSS (Harmonic Percussive Source Separation)
    - **Harmonic**: `██████████████████████████████` 70.0%
    - **Percussive**: `███████████████░░░░░░░░░░░░░░░` 30.0%
    
    ## 🎹 4. Tonalite & Chroma Map
    **Key Detection**: C Major (Majör Eğilimli)
    
    ## 🔍 5. Forensic DNA (Röntgen)
    | Feature | Status |
    | :--- | :--- |
    | **Bit-Depth Integrity** | 24-bit (✅ NATIVE) |
    """)
    .frame(width: 350)
    .padding()
}
