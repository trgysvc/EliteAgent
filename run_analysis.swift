import AudioIntelligence

@main
struct Analyzer {
    static func main() async {
        let filePath = "/Users/trgysvc/Downloads/La Napa (feat. Nidia Góngora).mp3"
        let url = URL(fileURLWithPath: filePath)
        
        print("Starting Deep Analysis for: \(url.lastPathComponent)")
        
        do {
            let builder = DNAReportBuilder()
            let (analysis, report, mdPath) = try await builder.analyze(url: url) { progress, message, _ in
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
