// MFCCEngine.swift
// Elite Music DNA Engine — Phase 2
//
// Librosa: feature.mfcc() — Mel → log → DCT-II (ortho)
// n_mfcc=20 (DNA raporu için 20 katsayı)

import Accelerate
import Foundation

public struct MFCCResult: Sendable {
    public let mfcc: [Float]           // [n_mfcc] — temporal mean
    public let delta: [Float]          // [n_mfcc] — MFCC delta (velocity)
    public let mfccMatrix: [[Float]]   // [n_mfcc × nFrames] — tüm frame'ler
}

public final class MFCCEngine: @unchecked Sendable {

    public let nMFCC: Int
    public let nMels: Int

    public init(nMFCC: Int = 20, nMels: Int = 128) {
        self.nMFCC = nMFCC
        self.nMels = nMels
    }

    // MARK: Compute MFCC

    /// Librosa: feature.mfcc(y, sr, n_mfcc=20, n_mels=128)
    /// 1. Mel spectrogram (power)
    /// 2. power_to_db (log scale)
    /// 3. DCT-II ortho → ilk 20 katsayı
    public func compute(melSpectrogram: [[Float]], stftEngine: STFTEngine) -> MFCCResult {
        let nFrames = melSpectrogram[0].count

        // power_to_db: 10 * log10(S / ref)
        let dbMel = stftEngine.powerToDb(melSpectrogram)

        // DCT-II her frame için
        var mfccMatrix = [[Float]](repeating: [Float](repeating: 0, count: nFrames), count: nMFCC)

        for t in 0..<nFrames {
            let frameLog = (0..<nMels).map { dbMel[$0][t] }
            let coeffs = DSPHelpers.dct2(frameLog, nCoeffs: nMFCC)
            for k in 0..<nMFCC {
                mfccMatrix[k][t] = coeffs[k]
            }
        }

        // Temporal mean
        var mfccMean = [Float](repeating: 0, count: nMFCC)
        for k in 0..<nMFCC {
            vDSP_meanv(mfccMatrix[k], 1, &mfccMean[k], vDSP_Length(nFrames))
        }

        // Delta MFCC (first derivative)
        let delta = computeDelta(mfccMatrix: mfccMatrix)

        return MFCCResult(mfcc: mfccMean, delta: delta, mfccMatrix: mfccMatrix)
    }

    // MARK: Delta (MFCC velocity)

    /// Librosa: feature.delta(data, width=9, order=1)
    /// Linear regression over 9-frame window
    private func computeDelta(mfccMatrix: [[Float]], width: Int = 9) -> [Float] {
        let nFrames = mfccMatrix[0].count
        let half = width / 2

        var delta = [Float](repeating: 0, count: nMFCC)

        for k in 0..<nMFCC {
            var sumDelta: Float = 0
            for t in half..<(nFrames - half) {
                // Slope via linear regression over window
                var num: Float = 0
                var den: Float = 0
                for d in -half...half {
                    let srcIdx = t + d
                    if srcIdx >= 0 && srcIdx < nFrames {
                        num += Float(d) * mfccMatrix[k][srcIdx]
                        den += Float(d * d)
                    }
                }
                sumDelta += den > 0 ? fabsf(num / den) : 0
            }
            delta[k] = nFrames > width ? sumDelta / Float(nFrames - width) : 0
        }

        return delta
    }
}
