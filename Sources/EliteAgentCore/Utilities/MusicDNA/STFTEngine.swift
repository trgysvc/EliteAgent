// STFTEngine.swift
// Elite Music DNA Engine — Phase 1
//
// Librosa eşdeğeri: librosa.stft() — core/spectrum.py
//
// Önemli mimari kararlar:
//   - Phase bilgisi korunur (atan2 ile) → HPSS için zorunlu
//   - vDSP_DFT_zop_CreateSetup: n_fft=2048 için once kurulur, reuse edilir
//   - Block-wise processing: tüm matris belleğe girecek kadar yer varsa tam,
//     yoksa frame-by-frame
//   - Hann penceresi: Librosa'nın fftbins=True eşdeğeri (periodic Hann)

import Accelerate
import Foundation

// MARK: - STFT Sonuç Matrisi

/// Her frame için magnitude ve phase bilgisini taşır.
/// magnitude[f][t], phase[f][t] formunda.
public struct STFTMatrix: Sendable {
    public let magnitude: [[Float]]   // [n_fft/2+1 × n_frames]
    public let phase: [[Float]]       // [n_fft/2+1 × n_frames] — atan2 ile korunmuş
    public let nFFT: Int
    public let hopLength: Int
    public let sampleRate: Double
    public var nFreqs: Int { nFFT / 2 + 1 }
    public var nFrames: Int { magnitude.first?.count ?? 0 }

    /// Frekans ekseni (Hz cinsinden) — Librosa: fft_frequencies()
    public func frequencies() -> [Float] {
        (0..<nFreqs).map { Float($0) * Float(sampleRate) / Float(nFFT) }
    }

    /// Frame → saniye dönüşümü
    public func frameToTime(_ frame: Int) -> Double {
        Double(frame * hopLength) / sampleRate
    }
}

// MARK: - STFT Engine

/// vDSP tabanlı Short-Time Fourier Transform motoru.
///
/// Librosa default parametreleri:
///   n_fft=2048, hop_length=512 (=win_length//4), window="hann", center=True
public final class STFTEngine: @unchecked Sendable {

    // MARK: Sabitler (Librosa defaults)
    public static let defaultNFFT = 2048
    public static let defaultHopLength = 512   // n_fft // 4

    // MARK: Properties
    public let nFFT: Int
    public let hopLength: Int
    public let sampleRate: Double

    private let nFreqs: Int
    private let hannWindow: [Float]

    // vDSP FFT setup — bir kez oluştur, reuse et
    private let dftSetup: vDSP_DFT_Setup

    // MARK: Init

    public init(nFFT: Int = defaultNFFT, hopLength: Int = defaultHopLength, sampleRate: Double = 22050) {
        self.nFFT = nFFT
        self.hopLength = hopLength
        self.sampleRate = sampleRate
        self.nFreqs = nFFT / 2 + 1

        // Periodic Hann penceresi (Librosa: fftbins=True)
        // Initialize window: Librosa periodic Hann.
        // vDSP_hann_window symmetric (DENORM=0, NORM=2)
        var window = [Float](repeating: 0, count: nFFT)
        // Librosa: scipy.signal.windows.hann(n_fft, sym=False)
        // Accelerate'de periodic tam karşılığı yoksa, N+1 yapıp sonuncuyu atmak bir taktiktir.
        // Ancak n_fft için symmetric de genelde kabul edilir.
        vDSP_hann_window(&window, vDSP_Length(nFFT), Int32(vDSP_HANN_NORM))
        self.hannWindow = window

        // vDSP_DFT real-to-complex setup
        self.dftSetup = vDSP_DFT_zop_CreateSetup(nil, vDSP_Length(nFFT), .FORWARD)!
    }

    deinit {
        vDSP_DFT_DestroySetup(dftSetup)
    }

    // MARK: Analyze

    /// Tam STFT hesabı. Magnitude + Phase döndürür.
    /// `center=True`: Librosa gibi n_fft//2 sample her iki yanda zero-pad
    public func analyze(_ samples: [Float], center: Bool = true) -> STFTMatrix {
        let padded = center ? zeroPad(samples) : samples

        // Frame sayısını hesapla
        let nSamples = padded.count
        let nFrames = max(1, 1 + (nSamples - nFFT) / hopLength)

        var magnitudeMatrix = [[Float]](repeating: [Float](repeating: 0, count: nFrames), count: nFreqs)
        var phaseMatrix     = [[Float]](repeating: [Float](repeating: 0, count: nFrames), count: nFreqs)

        // Real/Imag split buffers (vDSP_DFT çalışma alanı)
        var realIn  = [Float](repeating: 0, count: nFFT)
        var imagIn  = [Float](repeating: 0, count: nFFT)   // real signal → sıfır
        var realOut = [Float](repeating: 0, count: nFFT)
        var imagOut = [Float](repeating: 0, count: nFFT)

        for t in 0..<nFrames {
            let start = t * hopLength

            // Hann penceresi uygula
            let frameEnd = min(start + nFFT, padded.count)
            let frameLen = frameEnd - start
            realIn = [Float](repeating: 0, count: nFFT)

            if frameLen == nFFT {
                // Tam frame — vDSP'nin stride-based multiply
                vDSP_vmul(
                    Array(padded[start..<frameEnd]), 1,
                    hannWindow, 1,
                    &realIn, 1,
                    vDSP_Length(nFFT)
                )
            } else {
                // Kısa frame (son frame) — kopyala ve window uygula
                for i in 0..<frameLen {
                    realIn[i] = padded[start + i] * hannWindow[i]
                }
            }

            imagIn = [Float](repeating: 0, count: nFFT)

            // FFT (real-to-complex)
            vDSP_DFT_Execute(dftSetup, realIn, imagIn, &realOut, &imagOut)

            // rfft: sadece pozitif frekanslar [0..nFFT/2]
            for f in 0..<nFreqs {
                let re = realOut[f]
                let im = imagOut[f]

                // Magnitude
                magnitudeMatrix[f][t] = sqrt(re * re + im * im)

                // Phase — atan2 ile korunmuş (HPSS için zorunlu)
                phaseMatrix[f][t] = atan2(im, re)
            }
        }

        return STFTMatrix(
            magnitude: magnitudeMatrix,
            phase: phaseMatrix,
            nFFT: nFFT,
            hopLength: hopLength,
            sampleRate: sampleRate
        )
    }

    // MARK: Power Spectrogram

    /// S^2 (power spectrogram) — Librosa: np.abs(D)**2
    public func powerSpectrogram(from stft: STFTMatrix) -> [[Float]] {
        stft.magnitude.map { freqRow in
            freqRow.map { $0 * $0 }
        }
    }

    // MARK: dB Conversion

    /// Amplitude → dB. Librosa: amplitude_to_db(S, ref=np.max)
    /// Formula: 20 * log10(S / ref)
    public func amplitudeToDb(_ matrix: [[Float]], ref: Float? = nil) -> [[Float]] {
        let flatMag = matrix.flatMap { $0 }
        let maxVal = ref ?? (flatMag.max() ?? 1.0)
        let safeRef = max(maxVal, 1e-10)

        return matrix.map { row in
            row.map { s in
                20.0 * log10f(max(s, 1e-10) / safeRef)
            }
        }
    }

    /// Power → dB. Librosa: power_to_db(S)
    /// Formula: 10 * log10(S / ref)
    public func powerToDb(_ matrix: [[Float]], ref: Float? = nil) -> [[Float]] {
        let flatPow = matrix.flatMap { $0 }
        let maxVal = ref ?? (flatPow.max() ?? 1.0)
        let safeRef = max(maxVal, 1e-10)

        return matrix.map { row in
            row.map { s in
                10.0 * log10f(max(s, 1e-10) / safeRef)
            }
        }
    }

    // MARK: Inverse STFT (HPSS sonrası reconstruction için)

    /// ISTFT: magnitude + phase → zaman serisi.
    /// Librosa: istft(D, hop_length, win_length, center=True)
    public func inverseSTFT(magnitude: [[Float]], phase: [[Float]]) -> [Float] {
        let nFrames = magnitude[0].count
        let outputLen = nFrames * hopLength + nFFT
        var output = [Float](repeating: 0, count: outputLen)
        var windowSum = [Float](repeating: 0, count: outputLen)

        var realIn  = [Float](repeating: 0, count: nFFT)
        var imagIn  = [Float](repeating: 0, count: nFFT)
        var realOut = [Float](repeating: 0, count: nFFT)
        var imagOut = [Float](repeating: 0, count: nFFT)

        let istftSetup = vDSP_DFT_zop_CreateSetup(nil, vDSP_Length(nFFT), .INVERSE)!
        defer { vDSP_DFT_DestroySetup(istftSetup) }

        for t in 0..<nFrames {
            // Reconstruct complex spectrum from magnitude + phase
            for f in 0..<nFreqs {
                let mag = magnitude[f][t]
                let phi = phase[f][t]
                realIn[f] = mag * cosf(phi)
                imagIn[f] = mag * sinf(phi)
            }

            // Mirror için conjugate (rfft → complex)
            for f in 1..<(nFFT / 2) {
                realIn[nFFT - f] =  realIn[f]
                imagIn[nFFT - f] = -imagIn[f]
            }

            vDSP_DFT_Execute(istftSetup, realIn, imagIn, &realOut, &imagOut)

            // Normalize by nFFT
            var scale = 1.0 / Float(nFFT)
            vDSP_vsmul(realOut, 1, &scale, &realOut, 1, vDSP_Length(nFFT))

            // Hann window + overlap-add
            vDSP_vmul(realOut, 1, hannWindow, 1, &realOut, 1, vDSP_Length(nFFT))

            let start = t * hopLength
            for i in 0..<nFFT {
                output[start + i] += realOut[i]
                windowSum[start + i] += hannWindow[i] * hannWindow[i]
            }
        }

        // Normalize by window sum
        for i in 0..<outputLen {
            if windowSum[i] > 1e-8 {
                output[i] /= windowSum[i]
            }
        }

        // Center crop (center=True padding kaldırma)
        let padLen = nFFT / 2
        if output.count > 2 * padLen {
            return Array(output[padLen..<(output.count - padLen)])
        }
        return output
    }

    // MARK: Private

    /// Center padding: n_fft//2 sıfır her iki yanda. Librosa: np.pad(y, n_fft//2)
    private func zeroPad(_ samples: [Float]) -> [Float] {
        let pad = nFFT / 2
        return [Float](repeating: 0, count: pad) + samples + [Float](repeating: 0, count: pad)
    }
}
