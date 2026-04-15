// MusicDNATool.swift
// Elite Music DNA Engine — Phase 4
//
// AgentTool implementasyonu. ToolRegistry'e kaydedilmek üzere tasarlanmıştır.

import Foundation

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
    public let summary = "Professional MIR spectral audio analysis."
    public let description = """
    CRITICAL: ALWAYS use this tool for music analysis (BPM, Key, Spectral DNA). 
    DO NOT use shell commands (afinfo, mdls) as they lack spectral/MIR capabilities.
    Analiz eder: BPM, Key, Spektral özellikler, MFCC, HPSS ve yapısal segmentasyon.
    Sonuçlar otomatik olarak '~/Documents/AI Works' klasörüne kaydedilir.
    Parametre: path (string) — Ses dosyasının tam yolu.
    """
    public let ubid = 18 // Token '3' in Qwen 2.5

    public init() {}

    public func execute(params: [String: AnyCodable], session: Session) async throws -> String {

        guard let rawPath = params["path"]?.value as? String else {
            throw ToolError.missingParameter("`path` parametresi gerekli. Örnek: ~/Music/track.mp3")
        }

        let expandedPath = rawPath.hasPrefix("~")
            ? rawPath.replacingOccurrences(of: "~", with: FileManager.default.homeDirectoryForCurrentUser.path)
            : rawPath

        let url = URL(fileURLWithPath: expandedPath)

        guard FileManager.default.fileExists(atPath: url.path) else {
            throw ToolError.executionError("Dosya bulunamadı: \(expandedPath)")
        }

        let ext = url.pathExtension.lowercased()
        let supported = ["mp3", "wav", "m4a", "aac", "flac", "aiff", "caf"]
        guard supported.contains(ext) else {
            throw ToolError.invalidParameter("Desteklenmeyen format: \(ext). Desteklenenler: \(supported.joined(separator: ", "))")
        }

        // Header Banner
        let header = WaveformRenderer.header(filename: url.lastPathComponent)
        await session.streamOutput(header + "\n\n")

        // Analiz — progress callback ile live feedback
        let state = ProgressState()

        let result = try await DNAReportBuilder.analyze(url: url) { percent, message, waveformLine in
            // Waveform satırı — Thread-safe check
            if state.shouldSendWaveform(waveformLine), let wf = waveformLine {
                Task {
                    await session.streamOutput("Waveform:\n\(wf)\n\n")
                }
            }

            // Progress bar
            let bar = WaveformRenderer.progressBar(percent: percent, message: message)
            Task {
                await session.streamOutput("\r\(bar)")
            }
        }

        // Populate session metadata for UI integration
        await session.setAudioAnalysis(result.analysis)

        // Boş satır + final report
        await session.streamOutput("\n\n")
        await session.streamOutput(result.reportText)

        return """
        ✅ Analiz tamamlandı!
        📄 Rapor: \(result.mdPath)
        
        \(result.reportText)
        """
    }
}
