// WaveformView.swift
// Elite Music DNA Engine — UI Components
//
// High-fidelity SwiftUI waveform visualization.

import SwiftUI

public struct WaveformView: View {
    let peaks: [Float]
    let color: Color
    
    public init(peaks: [Float], color: Color = .accentColor) {
        self.peaks = peaks
        self.color = color
    }
    
    public var body: some View {
        GeometryReader { geo in
            let width = geo.size.width
            let height = geo.size.height
            let barWidth = max(2, width / CGFloat(peaks.count) - 1)
            
            HStack(alignment: .center, spacing: 1) {
                ForEach(0..<peaks.count, id: \.self) { i in
                    let peak = CGFloat(peaks[i])
                    let barHeight = peak * height
                    
                    RoundedRectangle(cornerRadius: 1)
                        .fill(
                            LinearGradient(
                                colors: [color, color.opacity(0.4)],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                        .frame(width: barWidth, height: max(2, barHeight))
                }
            }
            .frame(width: width, height: height)
        }
    }
}

#Preview {
    WaveformView(peaks: (0..<100).map { _ in Float.random(in: 0.1...0.9) })
        .frame(height: 100)
        .padding()
}
