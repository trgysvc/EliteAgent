// MusicDNACard.swift
// Elite Music DNA Engine — UI Components
//
// The premium "Röntgen" analysis card for the chat interface.

import SwiftUI
import EliteAgentCore

public struct MusicDNACard: View {
    let analysis: MusicDNAAnalysis
    let onOpenReport: () -> Void
    
    public init(analysis: MusicDNAAnalysis, onOpenReport: @escaping () -> Void) {
        self.analysis = analysis
        self.onOpenReport = onOpenReport
    }
    
    public var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // HEADER: File Info & Forensics
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(analysis.fileName)
                        .font(.headline)
                        .lineLimit(1)
                    
                    Text("DNA Analysis — \(analysis.timestamp.formatted(date: .omitted, time: .shortened))")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                
                Spacer()
                
                // Forensic Badges
                if let encoder = analysis.forensic.encoder {
                    Text(encoder.prefix(10))
                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(.blue.opacity(0.2))
                        .cornerRadius(4)
                }
            }
            
            // GRID: Core Metrics (Tempo, Key, Brightness, Dynamics)
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                MetricItem(label: "TEMPO", value: "\(Int(analysis.rhythm.bpm)) BPM", detail: "librosa beat_track")
                MetricItem(label: "TON", value: analysis.tonality.key, detail: "chroma match")
                MetricItem(label: "PARLAKLIK", value: "\(Int(analysis.spectral.centroid)) Hz", detail: "spectral_centroid")
                MetricItem(label: "DİNAMİK", value: "\(analysis.spectral.dynamicRange) dB", detail: "rms max/mean")
            }
            
            // WAVEFORM
            VStack(alignment: .leading, spacing: 4) {
                Text("BİYOLOJİK İZ (SPECTRAL PEAKS)")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(.secondary)
                
                WaveformView(peaks: analysis.waveformPeaks)
                    .frame(height: 48)
                    .padding(.vertical, 4)
            }
            
            // FOOTER: Report Link
            Button(action: onOpenReport) {
                HStack {
                    Image(systemName: "doc.text.magnifyingglass")
                    Text("Tam DNA Raporunu İncele (.md)")
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.caption2)
                }
                .font(.subheadline.bold())
                .padding()
                .frame(maxWidth: .infinity)
                .background(.ultraThinMaterial)
                .cornerRadius(12)
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(.primary.opacity(0.1), lineWidth: 0.5)
                )
            }
            .buttonStyle(.plain)
        }
        .padding()
        .background(.ultraThinMaterial)
        .cornerRadius(20)
        .overlay(
            RoundedRectangle(cornerRadius: 20)
                .stroke(.primary.opacity(0.1), lineWidth: 0.5)
        )
        .shadow(radius: 10, y: 5)
    }
}

private struct MetricItem: View {
    let label: String
    let value: String
    let detail: String
    
    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(.secondary)
            
            Text(value)
                .font(.system(.subheadline, design: .rounded).bold())
            
            Text(detail)
                .font(.system(size: 9))
                .foregroundStyle(.secondary.opacity(0.8))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
