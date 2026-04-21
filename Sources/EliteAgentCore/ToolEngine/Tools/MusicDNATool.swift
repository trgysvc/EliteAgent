// MusicDNATool.swift
// Elite Music DNA Engine — Phase 8 (v8.1.5 Infinity)
//
// AgentTool implementasyonu. ToolRegistry'e kaydedilmek üzere tasarlanmıştır.

import Foundation
import AudioIntelligence
import AudioIntelligenceCore

public struct MusicDNATool: AgentTool {
    public let name = "music_dna"
    public let summary = "Infinity Engine v8.1.5: 100% Depth Mastering, Forensic, Scholarly Musicology & Scientific SIR Audit."
    public let description = """
    CRITICAL: Full-Disclosure professional audio analysis (v8.1.5 Infinity).
    Capabilities:
    - Bilimsel Denetim (SIR): EBU R128 & AES17 Kalibrasyon Sertifikalı Analiz.
    - Donanım Telemetrisi: M4 Silicon (AMX/ANE) Hızlandırma Durumu.
    - Adli Denetim: Bit-Depth Entropy, Codec Cutoff, Clipping Audit, Forgery Detection.
    - Müzikolojik Denetim: Ur-Note Reduction, Ursatz Structure, Counterpoint, Historical Context.
    - Kapsamlı Araştırma: Full 26-engine deep dive (STFT, NMF, Tonnetz, Wavelet, Rhythm).
    
    Param: path (string) - Absolute path to the audio file.
    Param: depth (string, optional) - 'forensic', 'musicology', 'comprehensive'. Default: 'summary'.
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

        // v8.1.5: Copy-on-Process (Safety Cloning)
        let fm = FileManager.default
        let stagingDir = fm.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Caches/com.trgysvc.EliteAgent/Processing/MusicDNA", isDirectory: true)
        
        try? fm.createDirectory(at: stagingDir, withIntermediateDirectories: true)
        let stagedURL = stagingDir.appendingPathComponent(UUID().uuidString + "_" + url.lastPathComponent)
        
        do {
            try fm.copyItem(at: url, to: stagedURL)
        } catch {
            throw AgentToolError.executionError("GÜVENLİK HATASI: Çalışma kopyası oluşturulamadı.")
        }
        
        defer { try? fm.removeItem(at: stagedURL) }

        // v8.1.5: Modern Feature Mapping
        let depth = params["depth"]?.value as? String ?? "summary"
        var selectedFeatures: Set<AudioFeature> = [.spectral, .rhythm, .forensic, .mastering, .harmonic, .pitch, .semantic, .separation]
        
        if depth == "forensic" { selectedFeatures = [.forensic, .mastering, .spectral] }
        if depth == "musicology" { selectedFeatures = [.harmonic, .pitch, .semantic, .rhythm] }
        if depth == "comprehensive" { selectedFeatures = Set(AudioFeature.allCases) }

        let intelligence = AudioIntelligence(device: AudioIntelligenceCore.Device.automatic, mode: AudioIntelligenceCore.Mode.performance)

        // Pre-flight Scientific Calibration Sweep (SIR)
        let auditor = ScientificAuditor()
        let calibrationResult = auditor.runScenarioA()
        
        // v8.1.5: Runtime check for calibration status via Mirror to bypass accessibility-level desync in some build environments
        let mirror = Mirror(reflecting: calibrationResult)
        let isPassed = mirror.children.first { $0.label == "passed" }?.value as? Bool ?? false
        let sirStatus = isPassed ? "✅ CERTIFIED (EBU R128)" : "⚠️ CALIBRATION DRIFT"

        do {
            let result = try await intelligence.analyze(url: stagedURL, features: selectedFeatures) { percent, message, _ in
                let bar = WaveformRenderer.progressBar(percent: percent, message: "Infinity Engine v8.1.5: \(message)")
                Task { await session.streamOutput("\r\(bar)") }
            }

            // M4 Telemetry
            let hwStats = await intelligence.getHardwareStats()

            // Populate session metadata for the new Bento-Box UI
            await session.setAudioAnalysis(result.rawAnalysis)
            await session.markWidgetAsRendered()

            // Forensic & Musicology Gists
            let forensicStatus = result.rawAnalysis.forensic.isUpsampled ? "⚠️ FAKE HI-RES" : "✅ NATIVE BIT-DEPTH (\(result.rawAnalysis.forensic.effectiveBits)-bit)"
            let musicologyGist = "Ur-Note: \(result.rawAnalysis.reduction.fundamentalNote) | Context: \(result.rawAnalysis.musicology.context.suggestedPeriod)"

            let response = """
            [MusicDNA_INFINITY] v8.1.5 Analiz Tamamlandı.
            
            ### 🧬 Özet Rapor: \(url.lastPathComponent)
            - **Doğrulama (SIR)**: \(sirStatus)
            - **M4 Hızlandırma**: \(hwStats.acceleration) (\(hwStats.activeThreads) Threads)
            - **Orijinallik**: \(forensicStatus)
            - **Tempo**: \(String(format: "%.1f", result.rawAnalysis.rhythm.bpm)) BPM (\(result.rawAnalysis.rhythm.characterize))
            - **Tonalite**: \(result.rawAnalysis.tonality.key) (\(result.rawAnalysis.tonality.tendency))
            - **Müzikoloji**: \(musicologyGist)
            - **Sinyal/Gürültü (SNR)**: \(String(format: "%.2f", result.rawAnalysis.science.snr)) dB
            
            ---
            **Daha Fazla Detay İçin Seçenekler:**
            1. **Adli Denetim (Forensic)**: Bit-depth ve teknik doğrulama için odaklanmış rapor.
            2. **Müzikolojik Denetim (Musicology)**: Schenkerian analizi ve yapısal iskelet detayları.
            3. **Kapsamlı Rapor (Comprehensive)**: 26+ motorlu tam spektrum ve ham ikili (.plist) dökümü.
            
            📄 Detaylı Rapor: \(result.reportPath ?? targetPath(for: url))
            💾 Binary İmza: \( (result.reportPath as NSString?)?.deletingPathExtension ?? "N/A" ).plist
            """
            
            // Move report if needed (Legacy Support)
            if let sourcePath = result.reportPath {
                let target = targetPath(for: url)
                try? fm.removeItem(atPath: target)
                try? fm.moveItem(atPath: sourcePath, toPath: target)
                
                // Move plist as well (v8.1.5 Binary Standard)
                let sourcePlist = (sourcePath as NSString).deletingPathExtension + ".plist"
                let targetPlist = (target as NSString).deletingPathExtension + ".plist"
                try? fm.removeItem(atPath: targetPlist)
                try? fm.moveItem(atPath: sourcePlist, toPath: targetPlist)
            }

            return response
        } catch {
            throw AgentToolError.executionError("MusicDNA Analiz Hatası: \(error.localizedDescription)")
        }
    }
    
    private func targetPath(for url: URL) -> String {
        let workspaceReportsDir = "/Users/trgysvc/Documents/EliteAgentWorkspace/Reports/MusicDNA"
        try? FileManager.default.createDirectory(atPath: workspaceReportsDir, withIntermediateDirectories: true)
        let fileName = url.deletingPathExtension().lastPathComponent + ".dna.md"
        return (workspaceReportsDir as NSString).appendingPathComponent(fileName)
    }
}

