import XCTest
@testable import EliteAgentCore

final class FileToolTests: XCTestCase {
    
    var readTool: ReadFileTool!
    var writeTool: WriteFileTool!
    var session: Session!
    var workspaceURL: URL!
    
    override func setUp() async throws {
        readTool = ReadFileTool()
        writeTool = WriteFileTool()
        
        // Setup a temporary workspace
        workspaceURL = FileManager.default.temporaryDirectory.appendingPathComponent("EliteAgentTest_Files_\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: workspaceURL, withIntermediateDirectories: true)
        
        // Ensure isolation is ON for security tests
        await MainActor.run {
            AppSettings.shared.isWorkspaceIsolationEnabled = true
        }
        
        session = Session(workspaceURL: workspaceURL)
    }
    
    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: workspaceURL)
    }
    
    // MARK: - ReadFileTool Tests
    
    func testReadValidFile() async throws {
        let filePath = workspaceURL.appendingPathComponent("test.txt")
        let content = "Hello EliteAgent"
        try content.write(to: filePath, atomically: true, encoding: .utf8)
        
        let params: [String: AnyCodable] = ["path": AnyCodable("test.txt")]
        let result = try await readTool.execute(params: params, session: session)
        
        XCTAssertEqual(result, content)
    }
    
    func testReadOutsideWorkspaceBlocked() async throws {
        // Isolation is ON
        let params: [String: AnyCodable] = ["path": AnyCodable("/etc/passwd")]
        
        do {
            _ = try await readTool.execute(params: params, session: session)
            XCTFail("Should have blocked access to /etc/passwd")
        } catch let error {
            if case .executionError(let msg) = error {
                XCTAssertTrue(msg.contains("GÜVENLİK ENGELİ") || msg.contains("Isolation"), "Error: \(msg)")
            } else {
                XCTFail("Wrong error type: \(error)")
            }
        }
    }
    
    func testFileNotFound() async throws {
        let params: [String: AnyCodable] = ["path": AnyCodable("missing_file_123.txt")]
        
        do {
            _ = try await readTool.execute(params: params, session: session)
            XCTFail("Should throw for missing file")
        } catch let error {
            if case .executionError(let msg) = error {
                XCTAssertTrue(msg.contains("File not found"), "Error: \(msg)")
            } else {
                XCTFail("Wrong error type: \(error)")
            }
        }
    }
    
    func testBinaryFileDetection() async throws {
        let filePath = workspaceURL.appendingPathComponent("test.mp3")
        try Data().write(to: filePath)
        
        let params: [String: AnyCodable] = ["path": AnyCodable("test.mp3")]
        let result = try await readTool.execute(params: params, session: session)
        
        XCTAssertTrue(result.contains("AUDIO_FILE_DETECTED"), "Should detect audio file")
    }
    
    // MARK: - WriteFileTool Tests
    
    func testWriteToWorkspace() async throws {
        let params: [String: AnyCodable] = [
            "path": AnyCodable("new_file.txt"),
            "content": AnyCodable("Swift 6 Content")
        ]
        
        let result = try await writeTool.execute(params: params, session: session)
        XCTAssertTrue(result.contains("File written"), "Should confirm write")
        
        let savedContent = try String(contentsOf: workspaceURL.appendingPathComponent("new_file.txt"), encoding: .utf8)
        XCTAssertEqual(savedContent, "Swift 6 Content")
    }
    
    func testAutoCreateDirectories() async throws {
        let params: [String: AnyCodable] = [
            "path": AnyCodable("folder/sub/file.txt"),
            "content": AnyCodable("Deep content")
        ]
        
        _ = try await writeTool.execute(params: params, session: session)
        
        let fileURL = workspaceURL.appendingPathComponent("folder/sub/file.txt")
        XCTAssertTrue(FileManager.default.fileExists(atPath: fileURL.path), "Directories and file should be created")
    }
    
    func testOverwriteEmptyProtection() async throws {
        // 1. Create a file with content
        let filePath = workspaceURL.appendingPathComponent("protect.txt")
        try "Original".write(to: filePath, atomically: true, encoding: .utf8)
        
        // 2. Try to overwrite with empty content without force
        let params: [String: AnyCodable] = [
            "path": AnyCodable("protect.txt"),
            "content": AnyCodable("")
        ]
        
        do {
            _ = try await writeTool.execute(params: params, session: session)
            XCTFail("Should have blocked empty overwrite without force")
        } catch let error {
            if case .executionError(let msg) = error {
                XCTAssertTrue(msg.contains("truncation protection"), "Error: \(msg)")
            } else {
                XCTFail("Wrong error type: \(error)")
            }
        }
        
        // 3. Try with force
        let forceParams: [String: AnyCodable] = [
            "path": AnyCodable("protect.txt"),
            "content": AnyCodable(""),
            "force": AnyCodable(true)
        ]
        _ = try await writeTool.execute(params: forceParams, session: session)
        let newContent = try String(contentsOf: filePath, encoding: .utf8)
        XCTAssertTrue(newContent.isEmpty, "Should allow empty write with force")
    }
    
    func testBinaryOverwriteProtection() async throws {
        let filePath = workspaceURL.appendingPathComponent("test.png")
        try Data().write(to: filePath)
        
        let params: [String: AnyCodable] = [
            "path": AnyCodable("test.png"),
            "content": AnyCodable("random text")
        ]
        
        do {
            _ = try await writeTool.execute(params: params, session: session)
            XCTFail("Should have blocked text write to binary file")
        } catch let error {
            if case .executionError(let msg) = error {
                XCTAssertTrue(msg.contains("binary dosyası"), "Error: \(msg)")
            } else {
                XCTFail("Wrong error type: \(error)")
            }
        }
    }
    
    func testWriteOutsideWorkspaceBlocked() async throws {
        let params: [String: AnyCodable] = [
            "path": AnyCodable("/tmp/elite_evil.txt"),
            "content": AnyCodable("malicious")
        ]
        
        do {
            _ = try await writeTool.execute(params: params, session: session)
            XCTFail("Should have blocked write outside workspace")
        } catch let error {
            if case .executionError(let msg) = error {
                XCTAssertTrue(msg.contains("GÜVENLİK ENGELİ") || msg.contains("outside allowed boundaries"), "Error: \(msg)")
            } else {
                XCTFail("Wrong error type: \(error)")
            }
        }
    }
}
