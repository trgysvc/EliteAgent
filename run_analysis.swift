import Foundation
import AudioToolbox
import Accelerate

// We'll define the necessary parts of the report generation here to avoid complex linking
// since we are running in a scratch context.
// Alternatively, I will just call the DNAReportBuilder.analyze if I compile all files.

@main
struct Analyzer {
    static func main() async {
        let filePath = "/Users/trgysvc/Downloads/La Napa (feat. Nidia Góngora).mp3"
        let url = URL(fileURLWithPath: filePath)
        
        print("Starting Deep Analysis for: \(url.lastPathComponent)")
        
        do {
            // We use the DNAReportBuilder directly from the sources we provide to swiftc
            let (analysis, report, mdPath) = try await DNAReportBuilder.analyze(url: url) { progress, message, _ in
                print("[\(Int(progress))%] \(message)")
            }
            
            print("\nAnalysis Complete!")
            print("Report saved to: \(mdPath)")
            print("\n--- REPORT PREVIEW ---")
            print(report.prefix(500))
            print("...")
            
        } catch {
            print("Error during analysis: \(error)")
        }
    }
}
