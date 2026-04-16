import Foundation
import AudioIntelligence

@main
struct InfinityAuditor {
    static func main() async {
        let path = "/Users/trgysvc/Developer/EliteAgent/analysis_target.mp3"
        print("🎙️ AudioIntelligence [v28.0]: Initializing Infinity Audit for \(path)...")
        
        let intelligence = AudioIntelligence(device: .current, mode: .balanced)
        let fileURL = URL(fileURLWithPath: path)
        
        do {
            let report = try await intelligence.analyze(
                url: fileURL,
                features: [.rhythm, .forensic, .mastering, .advancedDSP]
            )
            
            print("\n✅ Infinity DNA Report [100% Depth]:")
            print("-------------------------")
            print("Summary: \(report.summary)")
            print("BPM: \(report.rawAnalysis.rhythm.bpm)")
            print("Rhythm: \(report.rawAnalysis.rhythm.tempoDescriptor)")
            print("Spectrum Flux: \(report.rawAnalysis.advancedDSP.spectralFlux.prefix(5))...")
            print("HPSS (Harmonic): \(report.rawAnalysis.advancedDSP.harmonicComponent.prefix(5))...")
            print("MFCC (Timbre): \(report.rawAnalysis.timbre.mfccMean.prefix(5))...")
            print("Encoder: \(report.rawAnalysis.forensic.encoder ?? "Native Source")")
            print("Bitrate Check: \(report.rawAnalysis.forensic.estimatedBitrate) kbps")
            print("Phase: \(report.rawAnalysis.mastering.phaseCorrelation)")
            print("L/R Balance: \(report.rawAnalysis.mastering.stereoBalance)")
            print("Loudness: \(report.rawAnalysis.mastering.integratedLUFS) LUFS")
            print("Peak: \(report.rawAnalysis.mastering.truePeak) dBTP")
            print("-------------------------")
            print("\n[MusicDNA_WIDGET] Generated successfully.")
            
        } catch {
            print("❌ Error during analysis: \(error)")
        }
    }
}
