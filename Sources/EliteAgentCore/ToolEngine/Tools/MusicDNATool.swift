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
    public let summary = "Infinity Engine: 100% Depth Mastering, Forensic & Audio Science Audit (v28.0)."
    public let description = """
    CRITICAL: Full-Disclosure professional audio analysis. NEVER shorten results.
    V28.0 Infinity Capabilities:
    - Mastering: LUFS (Int/Mom/Short), True Peak, Phase Correlation, L/R Balance.
    - Pitch DNA: Mean F0 (Hz), Voiced Ratio, Entonation Stability.
    - Timbre: 20 MFCCs, 7nd-Band Spectral Contrast chart, Flatness, ZCR. 
    - Forensic: Bit-Depth Entropy, Upsampling detection, Encoder Footprint.
    - Structure: Automated segment detection (Intro, Chorus, etc.).
    - MIR: BPM (Ellis DP), Chromagram (C-B notes), Key Detection.
    
    Param: path (string) - Absolute path to the audio file.
    Param: features (list, optional) - Custom focus: 'spectral', 'rhythm', 'forensic'.
    """
    public let ubid: Int128 = 18


    public init() {}

    public func execute(params: [String: AnyCodable], session: Session) async throws(AgentToolError) -> String {

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

        // v26.0: Copy-on-Process (Safety Cloning)
        let fm = FileManager.default
        let stagingDir = fm.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Caches/com.trgysvc.EliteAgent/Processing/MusicDNA", isDirectory: true)
        
        try? fm.createDirectory(at: stagingDir, withIntermediateDirectories: true)
        
        let stagedURL = stagingDir.appendingPathComponent(UUID().uuidString + "_" + url.lastPathComponent)
        
        do {
            try fm.copyItem(at: url, to: stagedURL)
            AgentLogger.logAudit(level: .info, agent: "MusicDNATool", message: "🛡 Safe Clone Created: \(stagedURL.path)")
        } catch {
            throw AgentToolError.executionError("GÜVENLİK HATASI: Çalışma kopyası oluşturulamadı. Orijinal dosyayı korumak için analiz durduruldu. Hata: \(error.localizedDescription)")
        }
        
        // v26.1: Automatic Cleanup - Delete clone after execution (Success or Failure)
        defer {
            try? fm.removeItem(at: stagedURL)
            AgentLogger.logAudit(level: .info, agent: "MusicDNATool", message: "🧹 Staging Cleaned: \(stagedURL.path)")
        }


        // v28.0: Map features
        var selectedFeatures: Set<AudioFeature> = [.spectral, .rhythm, .forensic]
        if let customFeatures = params["features"]?.value as? [String] {
            selectedFeatures = Set(customFeatures.compactMap { AudioFeature(rawValue: $0) })
            if selectedFeatures.isEmpty { selectedFeatures = [.spectral, .rhythm, .forensic] }
        }

        // Analiz — Using the Professional Package Actor on the SAFE CLONE
        let intelligence = AudioIntelligence(device: .current, mode: .balanced)
        let state = ProgressState()

        do {
            let result = try await intelligence.analyze(url: stagedURL, features: selectedFeatures) { percent, message, waveformLine in
                // Visual feedback

                if state.shouldSendWaveform(waveformLine), let wf = waveformLine {
                    Task { await session.streamOutput("Waveform:\n\(wf)\n\n") }
                }

                let bar = WaveformRenderer.progressBar(percent: percent, message: message)
                Task { await session.streamOutput("\r\(bar)") }
            }

            // Populate session metadata for UI integration
            await session.setAudioAnalysis(result.rawAnalysis)

            // v25.0: Relocate report to User Workspace
            let workspaceReportsDir = "/Users/trgysvc/Documents/EliteAgentWorkspace/Reports/MusicDNA"
            let fm = FileManager.default
            try? fm.createDirectory(atPath: workspaceReportsDir, withIntermediateDirectories: true)
            
            let sourcePath = result.reportPath
            let fileName = URL(fileURLWithPath: sourcePath).lastPathComponent
            let targetPath = (workspaceReportsDir as NSString).appendingPathComponent(fileName)
            
            // Move file if not already there
            if sourcePath != targetPath {
                try? fm.removeItem(atPath: targetPath)
                try? fm.moveItem(atPath: sourcePath, toPath: targetPath)
            }

            // Final report
            await session.streamOutput("\n\n")
            await session.streamOutput(result.reportText)

            let forensicMsg = result.rawAnalysis.forensic.isUpsampled ? "⚠️ FAKE HI-RES (Upsampled)" : "✅ NATIVE BIT-DEPTH"
            let segmentsMsg = "\(result.rawAnalysis.segments.count) segments detected"

            return """
            [MusicDNA_INFINITY] ✅ v28.0 Deep Audit Complete.
            🛡 Integrity: \(forensicMsg) (\(result.rawAnalysis.forensic.effectiveBits)-bit)
            🧩 Structure: \(segmentsMsg)
            📄 Rapor: \(targetPath)
            
            \(result.reportText)
            """
        } catch {
            throw AgentToolError.executionError("MusicDNA Analiz Hatası: \(error.localizedDescription)")
        }

    }
}
