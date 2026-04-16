import XCTest
import Foundation
@testable import EliteAgentCore
// Note: We might need to import AudioIntelligence directly if it's available in the test target
import AudioIntelligenceCore

final class AudioAnalysisExecution: XCTestCase {
    
    func testExecuteMusicDNAAnalysis() async throws {
        let filePath = "/Users/trgysvc/Downloads/La Napa (feat. Nidia Góngora).mp3"
        let url = URL(fileURLWithPath: filePath)
        
        XCTAssertTrue(FileManager.default.fileExists(atPath: filePath), "Audio file must exist at path: \(filePath)")
        
        print("--- STARTING AUDIO ANALYSIS ---")
        print("Target: \(filePath)")
        
        // We use DNAReportBuilder which is part of AudioIntelligenceCore
        // and is also used by MusicDNATool
        
        let expectation = XCTestExpectation(description: "Analysis completion")
        
        do {
            let (analysis, report, mdPath) = try await DNAReportBuilder.analyze(url: url) { progress, message, _ in
                print("[\(Int(progress))%] \(message)")
            }
            
            print("\nAnalysis Success!")
            print("Generated Report Markdown: \(mdPath)")
            print("\nReport Content Preview:\n")
            print(report.prefix(1000))
            print("\n... (truncated) ...\n")
            
            XCTAssertTrue(FileManager.default.fileExists(atPath: mdPath), "MD report should be created at: \(mdPath)")
            expectation.fulfill()
        } catch {
            XCTFail("Analysis failed with error: \(error)")
        }
        
        await fulfillment(of: [expectation], timeout: 600) // 10 minutes timeout for deep analysis
    }
}
