// RhythmEngine.swift
// Elite Music DNA Engine — Phase 2
//
// Librosa eşdeğeri:
//   feature.tempo() — BPM tahmini (autocorrelation tabanlı)
//   beat.beat_track() — Ellis DP beat tracker (kaynak koddan birebir)
//
// ÖNEMLİ: Beat DP döngüsü actor içinde çalışır (UI kilitsiz)

import Accelerate
import Foundation

// MARK: - Sonuç Yapısı

public struct RhythmResult: Sendable {
    public let bpm: Float
    public let beatTimes: [Double]      // saniye cinsinden beat konumları
    public let beatFrames: [Int]        // frame indexleri
    public let gridStdSec: Double       // beat timing regularity (std dev of intervals)
    public let onsetMean: Float
    public let onsetPeak: Float
}

// MARK: - Beat Tracking Actor (UI-Safe)

/// DP döngüsü binlerce iterasyon — actor ile UI thread'ini kilitmiyoruz.
public actor BeatTrackingActor {

    // MARK: Tempo Estimation

    /// BPM tahmini: onset envelope autocorrelation → tempo range [60, 180]
    /// Librosa: feature.tempo(onset_envelope, sr, hop_length, start_bpm=120)
    func estimateTempo(
        onsetEnvelope: [Float],
        sampleRate: Double,
        hopLength: Int,
        startBPM: Float = 120.0
    ) -> Float {
        let frameRate = Float(sampleRate) / Float(hopLength)

        // Autocorrelation of onset envelope
        let acf = DSPHelpers.autocorrelate(onsetEnvelope, maxSize: onsetEnvelope.count)

        // BPM range → frame lag range
        let minBPM: Float = 60.0
        let maxBPM: Float = 240.0
        let lagMin = Int(frameRate * 60.0 / maxBPM)
        let lagMax = Int(frameRate * 60.0 / minBPM)

        guard lagMin < lagMax && lagMax < acf.count else {
            return startBPM
        }

        // Find peak in lag range
        var bestLag = lagMin
        var bestVal: Float = -Float.infinity

        for lag in lagMin...min(lagMax, acf.count - 1) {
            if acf[lag] > bestVal {
                bestVal = acf[lag]
                bestLag = lag
            }
        }

        let estimatedBPM = frameRate * 60.0 / Float(bestLag)

        // Harmonic tempo preference: prefer tempo near start_bpm
        // Librosa: checks 0.5x, 1x, 2x of estimated tempo
        let candidates: [Float] = [estimatedBPM / 2, estimatedBPM, estimatedBPM * 2]
        let best = candidates.min(by: { abs(logf($0 / startBPM)) < abs(logf($1 / startBPM)) })
        return best ?? estimatedBPM
    }

    // MARK: Ellis DP Beat Tracker

    /// Librosa beat.py → __beat_tracker() birebir implementasyonu.
    /// 3 aşama: localscore hesabı → DP → backtracking + trim
    func beatTrack(
        onsetEnvelope: [Float],
        bpm: Float,
        sampleRate: Double,
        hopLength: Int,
        tightness: Float = 100.0,
        trim: Bool = true
    ) -> [Int] {
        let frameRate = Float(sampleRate) / Float(hopLength)
        let framesPerBeat = frameRate * 60.0 / bpm   // float FPB

        // Step 1: Normalize onsets by std (Librosa: __normalize_onsets)
        let n = onsetEnvelope.count
        var mean: Float = 0
        var stddev: Float = 0
        vDSP_meanv(onsetEnvelope, 1, &mean, vDSP_Length(n))

        var variance: Float = 0
        let centered = onsetEnvelope.map { $0 - mean }
        vDSP_measqv(centered, 1, &variance, vDSP_Length(n))
        stddev = sqrtf(variance)
        let normOnsets = stddev > 1e-8 ? onsetEnvelope.map { $0 / stddev } : onsetEnvelope

        // Step 2: Local score = Gaussian convolution of normalized onset
        // window = exp(-0.5 * (arange(-fpb, fpb+1) * 32 / fpb)^2)
        let localscore = gaussianConvolve(normOnsets, halfWidth: Int(framesPerBeat))

        // Step 3: Dynamic Programming (Ellis 2007)
        var cumscore  = [Float](repeating: 0, count: n)
        var backlink  = [Int](repeating: -1, count: n)
        let scoreThresh = 0.01 * (localscore.max() ?? 0)
        var firstBeat = true

        for i in 0..<n {
            cumscore[i] = localscore[i]
            var bestScore: Float = -Float.infinity
            var bestLoc = -1

            let searchStart = max(0, i - Int(framesPerBeat / 2))
            let searchEnd   = max(0, i - Int(2 * framesPerBeat))

            for loc in stride(from: searchStart, through: searchEnd, by: -1) {
                let logRatio = log(Float(i - loc)) - log(framesPerBeat)
                let score = cumscore[loc] - tightness * logRatio * logRatio
                if score > bestScore {
                    bestScore = score
                    bestLoc = loc
                }
            }

            if bestLoc >= 0 {
                cumscore[i] = localscore[i] + bestScore
                if firstBeat && localscore[i] < scoreThresh {
                    backlink[i] = -1
                } else {
                    backlink[i] = bestLoc
                    firstBeat = false
                }
            }
        }

        // Step 4: Find last beat (highest cumscore local max above 0.5*median)
        let localMaxima = DSPHelpers.localMax(cumscore)
        let maxSorted = localMaxima.map { cumscore[$0] }.sorted()
        let medianScore = maxSorted.isEmpty ? 0 : maxSorted[maxSorted.count / 2]
        let threshold = 0.5 * medianScore

        var tail = n - 1
        for i in stride(from: n - 1, through: 0, by: -1) {
            if localMaxima.contains(i) && cumscore[i] >= threshold {
                tail = i
                break
            }
        }

        // Step 5: Backtrack
        var beats: [Int] = []
        var current = tail
        while current >= 0 {
            beats.append(current)
            current = backlink[current]
        }
        beats.reverse()

        // Step 6: Trim weak leading/trailing beats
        if trim {
            beats = trimBeats(beats, localscore: localscore)
        }

        return beats
    }

    // MARK: Private Helpers

    /// Gaussian window convolution (localscore hesabı)
    /// window = exp(-0.5 * (delta * 32 / fpb)^2) for delta in [-fpb..fpb]
    private func gaussianConvolve(_ signal: [Float], halfWidth: Int) -> [Float] {
        let n = signal.count
        let fpb = Float(halfWidth)
        let wSize = 2 * halfWidth + 1

        var window = (0..<wSize).map { k -> Float in
            let delta = Float(k - halfWidth)
            return expf(-0.5 * (delta * 32.0 / fpb) * (delta * 32.0 / fpb))
        }

        // Normalize window
        let windowSum = window.reduce(0, +)
        if windowSum > 0 { window = window.map { $0 / windowSum } }

        // Same-mode convolution
        var result = [Float](repeating: 0, count: n)
        for i in 0..<n {
            var val: Float = 0
            for k in 0..<wSize {
                let srcIdx = i + k - halfWidth
                if srcIdx >= 0 && srcIdx < n {
                    val += window[k] * signal[srcIdx]
                }
            }
            result[i] = val
        }
        return result
    }

    /// Trim weak leading/trailing beats.
    /// Librosa: __trim_beats — threshold = 0.5 * RMS of Hann-smoothed beat onsets
    private func trimBeats(_ beats: [Int], localscore: [Float]) -> [Int] {
        guard !beats.isEmpty else { return beats }

        let beatScores = beats.map { localscore[$0] }
        let rms = sqrtf(beatScores.map { $0 * $0 }.reduce(0, +) / Float(beatScores.count))
        let threshold = 0.5 * rms

        var trimmed = beats
        while let first = trimmed.first, localscore[first] <= threshold {
            trimmed.removeFirst()
        }
        while let last = trimmed.last, localscore[last] <= threshold {
            trimmed.removeLast()
        }
        return trimmed
    }
}

// MARK: - RhythmEngine (Public Interface)

public final class RhythmEngine: @unchecked Sendable {

    private let sampleRate: Double
    private let hopLength: Int
    private let actor = BeatTrackingActor()

    public init(sampleRate: Double = 22050, hopLength: Int = 512) {
        self.sampleRate = sampleRate
        self.hopLength = hopLength
    }

    /// Ana analiz fonksiyonu. Actor içinde DP çalıştırır (async).
    public func analyze(onsetResult: OnsetResult) async -> RhythmResult {
        let envelope = onsetResult.envelope

        // BPM tahmini
        let bpm = await actor.estimateTempo(
            onsetEnvelope: envelope,
            sampleRate: sampleRate,
            hopLength: hopLength,
            startBPM: 120.0
        )

        // Beat tracking (DP)
        let beatFrames = await actor.beatTrack(
            onsetEnvelope: envelope,
            bpm: bpm,
            sampleRate: sampleRate,
            hopLength: hopLength
        )

        // Beat times
        let beatTimes = beatFrames.map { Double($0 * hopLength) / sampleRate }

        // Grid std: std dev of beat intervals → timing regularity
        let intervals = zip(beatTimes, beatTimes.dropFirst()).map { $1 - $0 }
        let gridStd: Double
        if intervals.count > 1 {
            let meanInterval = intervals.reduce(0, +) / Double(intervals.count)
            let variance = intervals.map { ($0 - meanInterval) * ($0 - meanInterval) }.reduce(0, +) / Double(intervals.count)
            gridStd = sqrt(variance)
        } else {
            gridStd = 0
        }

        return RhythmResult(
            bpm: bpm,
            beatTimes: beatTimes,
            beatFrames: beatFrames,
            gridStdSec: gridStd,
            onsetMean: onsetResult.mean,
            onsetPeak: onsetResult.peak
        )
    }
}
