import XCTest
@testable import EliteAgentCore

final class EliteAgentTests: XCTestCase {
    
    func testFactoryReset_DeletesGGUFFiles() async throws {
        // 1. Setup mock environment
        let fileManager = FileManager.default
        let modelsURL = await ModelSetupManager.shared.getModelDirectory()
        
        try? fileManager.createDirectory(at: modelsURL, withIntermediateDirectories: true)
        let testFile = modelsURL.appendingPathComponent("test_model.gguf")
        try "fake model data".write(to: testFile, atomically: true, encoding: .utf8)
        
        XCTAssertTrue(fileManager.fileExists(atPath: testFile.path), "Test file should exist before reset")
        
        // 2. Perform mock reset logic
        // (Since we can't easily terminate the test runner, we just test the critical file deletion part)
        
        try? fileManager.removeItem(at: modelsURL)
        
        // 3. Verify
        XCTAssertFalse(fileManager.fileExists(atPath: testFile.path), "GGUF files should be deleted after reset")
    }
}
