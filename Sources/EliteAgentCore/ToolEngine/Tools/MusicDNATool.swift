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
    public let description = """
    Bir ses dosyasının (MP3, WAV, M4A, FLAC, AAC) tam müzik DNA'sını analiz eder.
    BPM, Key, Spektral özellikler, MFCC, HPSS ve yapısal segmentasyon hesaplar.
    Analiz sırasında live waveform ve ilerleme gösterir.
    Sonucu chat penceresinde raporlar, .dna.md ve .dna.json olarak kaydeder.
    Parametre: path (string) — Ses dosyasının tam yolu.
    """

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

        // Boş satır + final report
        await session.streamOutput("\n\n")
        await session.streamOutput(result.reportText)

        return """
        ✅ Analiz tamamlandı!
        📄 Markdown: \(result.mdPath)
        📊 JSON: \(result.jsonPath)
        
        \(result.reportText)
        """
    }
}
