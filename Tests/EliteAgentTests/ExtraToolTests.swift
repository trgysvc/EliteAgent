import XCTest
@testable import EliteAgentCore

final class EliteExtraToolTests: XCTestCase {
    
    var gitTool: GitTool!
    var searchTool: WebSearchToolWrapper!
    var fetchTool: WebFetchToolWrapper!
    var session: Session!
    var workspaceURL: URL!
    
    override func setUp() async throws {
        gitTool = GitTool()
        searchTool = WebSearchToolWrapper()
        fetchTool = WebFetchToolWrapper()
        
        // Setup a temporary workspace
        workspaceURL = FileManager.default.temporaryDirectory.appendingPathComponent("EliteAgentTest_Extra_\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: workspaceURL, withIntermediateDirectories: true)
        
        session = Session(workspaceURL: workspaceURL)
        
        // Setup VaultManager for tests
        let vaultURL = workspaceURL.appendingPathComponent("vault.plist")
        let manager = try VaultManager(configURL: vaultURL)
        await MainActor.run {
            VaultManager.shared = manager
        }
        
        // Point GitStateEngine to our test workspace
        await GitStateEngine.shared.setProjectRoot(workspaceURL.path)
    }
    
    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: workspaceURL)
    }
    
    // MARK: - GitTool Tests
    
    func testGitStatusNonRepo() async throws {
        let params: [String: AnyCodable] = ["action": AnyCodable("status")]
        let result = try await gitTool.execute(params: params, session: session)
        XCTAssertNotNil(result)
    }
    
    func testGitInitAndCommit() async throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        process.arguments = ["init"]
        process.currentDirectoryURL = workspaceURL
        try process.run()
        process.waitUntilExit()
        
        let configProcess = Process()
        configProcess.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        configProcess.arguments = ["config", "user.name", "TestUser"]
        configProcess.currentDirectoryURL = workspaceURL
        try configProcess.run()
        configProcess.waitUntilExit()
        
        let configEmailProcess = Process()
        configEmailProcess.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        configEmailProcess.arguments = ["config", "user.email", "test@example.com"]
        configEmailProcess.currentDirectoryURL = workspaceURL
        try configEmailProcess.run()
        configEmailProcess.waitUntilExit()
        
        let testFile = workspaceURL.appendingPathComponent("hello.txt")
        try "world".write(to: testFile, atomically: true, encoding: .utf8)
        
        let params: [String: AnyCodable] = [
            "action": AnyCodable("commit"),
            "message": AnyCodable("Initial commit")
        ]
        
        let result = try await gitTool.execute(params: params, session: session)
        XCTAssertTrue(result.contains("SUCCESS"))
    }
    
    // MARK: - WebSearchTool Tests
    
    func testSearchFallback() async throws {
        let params: [String: AnyCodable] = ["query": AnyCodable("Swift 6")]
        let result = try await searchTool.execute(params: params, session: session)
        XCTAssertFalse(result.isEmpty)
    }
}
