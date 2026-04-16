// MusicDNATool.swift
// Elite Music DNA Engine — Phase 4
//
// AgentTool implementasyonu. ToolRegistry'e kaydedilmek üzere tasarlanmıştır.

import Foundation
import AudioIntelligence
import AudioIntelligenceCore // For raw data mapping if needed

// Helper to track progress state across @Sendable closures
private final class ProgressState: @unchecked Sendable {
    var lastWaveform: String? = nil
    private let lock = NSLock()
    
    func shouldSendWaveform(_ wf: String?) -> Bool {
        lock.lock(); defer { lock.unlock() }
        if wf != nil && lastWaveform == nil {
            lastWaveform = wf
            return true
        }
        return false
    }
}

public struct MusicDNATool: AgentTool {
    public let name = "music_dna"
    public let summary = "Infinity Engine: 100% Depth Mastering & Audio Science Audit."
    public let description = """
    CRITICAL: Full-Disclosure professional audio analysis. NEVER shorten results.
    Analyzes: 
    - Mastering: Integrated/Momentary/Short-term LUFS, True Peak, Phase Correlation, L/R Balance.
    - Timbre: Full 20 MFCC coefficients, Spectral Flux, Flatness, ZCR, Bandwidth. 
    - Science: HPSS (Harmonic/Percussive) energy ratios, Bit-Depth Entropy.
    - MIR: BPM (Ellis DP), Key Detection, Foote Structure Segmentation.
    
    Interpretive Guidelines: Always reference HPSS ratios and MFCC vectors for deep timbre descriptions.
    Param: path (string) - Absolute path to the audio file.
    """
    public let ubid = 18

    public init() {}

    public func execute(params: [String: AnyCodable], session: Session) async throws -> String {

        guard let rawPath = params["path"]?.value as? String else {
            throw AgentToolError.missingParameter("`path` parametresi gerekli.")
        }

        let expandedPath = rawPath.hasPrefix("~")
            ? rawPath.replacingOccurrences(of: "~", with: FileManager.default.homeDirectoryForCurrentUser.path)
            : rawPath

        let url = URL(fileURLWithPath: expandedPath)

        guard FileManager.default.fileExists(atPath: url.path) else {
            throw AgentToolError.executionError("Dosya bulunamadı: \(expandedPath)")
        }

        // Header Banner
        let header = WaveformRenderer.header(filename: url.lastPathComponent)
        await session.streamOutput(header + "\n\n")

        // Analiz — Using the Professional Package Actor
        let intelligence = AudioIntelligence(device: .current, mode: .balanced)
        let state = ProgressState()

        let result = try await intelligence.analyze(url: url) { percent, message, waveformLine in
            // Visual feedback
            if state.shouldSendWaveform(waveformLine), let wf = waveformLine {
                Task { await session.streamOutput("Waveform:\n\(wf)\n\n") }
            }

            let bar = WaveformRenderer.progressBar(percent: percent, message: message)
            Task { await session.streamOutput("\r\(bar)") }
        }

        // Populate session metadata for UI integration
        await session.setAudioAnalysis(result.rawAnalysis)

        // Final report
        await session.streamOutput("\n\n")
        await session.streamOutput(result.reportText)

        return """
        [MusicDNA_WIDGET] ✅ Analiz tamamlandı! (AudioIntelligence Package)
        📄 Rapor: \(result.reportPath)
        
        \(result.reportText)
        """
    }
}
