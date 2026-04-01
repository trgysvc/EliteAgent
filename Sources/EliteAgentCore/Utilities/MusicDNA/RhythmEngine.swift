// RhythmEngine.swift
// Elite Music DNA Engine — Phase 3
//
// Onset Detection and Tempo Tracking.
// Mirroring librosa.onset.onset_detect and librosa.beat.beat_track.

import Foundation
import Accelerate

public struct RhythmResult: Sendable {
    public let bpm: Double
    public let beatFrames: [Int]
    public let beatTimes: [Double]
    public let gridStdSec: Double
    public let onsetMean: Float
    public let onsetPeak: Float
}

public final class RhythmEngine: Sendable {
    
    private let sampleRate: Double
    
    public init(sampleRate: Double = 44100) {
        self.sampleRate = sampleRate
    }
    
    public func analyze(onsetResult: OnsetResult) async -> RhythmResult {
        let bpm = RhythmEngine.estimateTempo(
            onsetStrength: onsetResult.envelope, 
            sr: sampleRate, 
            hopLength: 512
        )
        
        return RhythmResult(
            bpm: Double(bpm),
            beatFrames: onsetResult.onsetFrames,
            beatTimes: onsetResult.onsetTimes,
            gridStdSec: Double(onsetResult.mean), // Placeholder for std
            onsetMean: onsetResult.mean,
            onsetPeak: onsetResult.peak
        )
    }
    
    // MARK: - Onset Strength (Novelty Function)
    
    /// Librosa: onset.onset_strength()
    /// Computes the spectral flux (rectified difference) 
    /// which spikes at note onsets.
    public static func onsetStrength(from stft: STFTMatrix) -> [Float] {
        let nFreqs = stft.nFreqs
        let nFrames = stft.nFrames
        
        var strength = [Float](repeating: 0, count: nFrames)
        
        for t in 1..<nFrames {
            var flux: Float = 0
            for f in 0..<nFreqs {
                let current = stft.magnitude[f * nFrames + t]
                let previous = stft.magnitude[f * nFrames + (t - 1)]
                
                // Rectified difference: max(0, curr - prev)
                flux += max(0, current - previous)
            }
            strength[t] = flux
        }
        
        // Normalize
        let maxVal = strength.max() ?? 1.0
        return strength.map { $0 / max(maxVal, 1e-10) }
    }
    
    // MARK: - Tempo Tracking
    
    /// Librosa: beat.tempo()
    /// Estimates BPM using autocorrelation of the onset strength.
    public static func estimateTempo(onsetStrength: [Float], sr: Double, hopLength: Int) -> Float {
        let n = onsetStrength.count
        guard n > 0 else { return 120.0 }
        
        // 1. Autocorrelation
        var acorr = [Float](repeating: 0, count: n)
        vDSP_conv(onsetStrength, 1, Array(onsetStrength.reversed()), 1, &acorr, 1, vDSP_Length(n), vDSP_Length(n))
        
        // 2. Identify peak in the tempo range (40...240 BPM)
        // Convert lag to BPM: bpm = 60 * sr / (hop_length * lag)
        
        let minLag = Int(60.0 * Float(sr) / (Float(hopLength) * 240.0))
        let maxLag = Int(60.0 * Float(sr) / (Float(hopLength) * 40.0))
        
        var bestBPM = Float(120.0)
        var maxVal: Float = -1.0
        
        for lag in max(1, minLag)...min(n-1, maxLag) {
            let val = acorr[lag]
            if val > maxVal {
                maxVal = val
                bestBPM = 60.0 * Float(sr) / (Float(hopLength) * Float(lag))
            }
        }
        
        return bestBPM
    }
}
