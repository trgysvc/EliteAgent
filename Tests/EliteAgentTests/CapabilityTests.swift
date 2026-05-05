import XCTest
@testable import EliteAgentCore

/// Comprehensive capability tests: intent classification, tool resolution, and tool execution.
/// These tests run without a loaded LLM — they validate the orchestration layer independently.
final class CapabilityTests: XCTestCase {

    var session: Session!
    var workspaceURL: URL!

    override func setUp() async throws {
        workspaceURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("EliteAgentCapTest_\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: workspaceURL, withIntermediateDirectories: true)
        session = Session(workspaceURL: workspaceURL)
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: workspaceURL)
    }

    // MARK: - Intent Classification

    func testChatIntentClassification() {
        let classifier = TaskClassifier()
        XCTAssertEqual(classifier.classify(prompt: "selam nasılsın"), .chat)
        XCTAssertEqual(classifier.classify(prompt: "merhaba iyi misin"), .chat)
        XCTAssertEqual(classifier.classify(prompt: "teşekkürler harika iş"), .chat)
    }

    func testWeatherIntentClassification() {
        let classifier = TaskClassifier()
        XCTAssertEqual(classifier.classify(prompt: "istanbul hava durumu nasıl"), .weather)
        XCTAssertEqual(classifier.classify(prompt: "yarın yağmur yağacak mı"), .weather)
        XCTAssertEqual(classifier.classify(prompt: "ankara sıcaklık kaç derece"), .weather)
    }

    func testCodeIntentClassification() {
        let classifier = TaskClassifier()
        XCTAssertEqual(classifier.classify(prompt: "swift build hataları düzelt"), .codeGeneration)
        XCTAssertEqual(classifier.classify(prompt: "bu kodu optimize et"), .codeGeneration)
    }

    func testHardwareIntentClassification() {
        let classifier = TaskClassifier()
        XCTAssertEqual(classifier.classify(prompt: "cpu kullanımı nedir"), .hardware)
        XCTAssertEqual(classifier.classify(prompt: "ram ne kadar kullanılıyor"), .hardware)
        XCTAssertEqual(classifier.classify(prompt: "memory durumu nasıl"), .hardware)
    }

    func testResearchIntentClassification() {
        let classifier = TaskClassifier()
        XCTAssertEqual(classifier.classify(prompt: "mlx swift en son sürümünü araştır"), .research)
        XCTAssertEqual(classifier.classify(prompt: "search for swift concurrency best practices"), .research)
    }

    // MARK: - CategoryMapper Tool Name Validation

    func testCategoryMapperToolNamesMatchRealToolNames() {
        // All known real tool names — derived from tool.name properties
        let realToolNames: Set<String> = [
            // File & Code
            "shell_exec", "read_file", "write_file", "patch_file", "git_action", "xcode_engine",
            // Web & Research
            "web_search", "web_fetch", "browser_native", "safari_automation", "research_report",
            // Communication
            "send_message_via_whatsapp_or_imessage", "whatsapp_send", "send_email",
            // Media & Music
            "media_control", "music_dna", "id3_processor",
            // Vision & Accessibility
            "visual_audit", "analyze_image", "apple_accessibility",
            // System
            "app_launcher", "get_system_info", "get_system_telemetry", "learn_application_ui",
            "set_volume", "set_brightness", "system_sleep", "run_shortcut", "discover_shortcuts",
            // Productivity
            "apple_calendar", "apple_mail", "contacts_find", "file_manager_action",
            // Utility
            "get_weather", "calculator_op", "system_date", "set_timer", "memory",
            // 3D & Advanced
            "blender_3d", "subagent_spawn"
        ]

        let allCategories = TaskCategory.allCases
        var badNames: [(category: String, name: String)] = []
        for category in allCategories {
            let names = CategoryMapper.getTools(for: category)
            for name in names {
                if !realToolNames.contains(name) {
                    badNames.append((category: "\(category)", name: name))
                }
            }
        }
        XCTAssertTrue(badNames.isEmpty, "CategoryMapper uses non-existent tool names: \(badNames)")
    }

    func testVisionCategoryMapsToCorrectTools() {
        let tools = CategoryMapper.getTools(for: .vision)
        XCTAssertTrue(tools.contains("visual_audit"), "Vision category must include 'visual_audit' (ChicagoVisionTool — screen analysis)")
        XCTAssertTrue(tools.contains("analyze_image"), "Vision category must include 'analyze_image' (ImageAnalysisTool — file analysis)")
    }

    func testResearchCategoryHasWebSearch() {
        let tools = CategoryMapper.getTools(for: .research)
        XCTAssertTrue(tools.contains("web_search"), "Research must include 'web_search'")
        XCTAssertFalse(tools.contains("google_search"), "'google_search' does not exist — use 'web_search'")
        XCTAssertTrue(tools.contains("browser_native"), "Research must include 'browser_native'")
        XCTAssertFalse(tools.contains("native_browser"), "Old name 'native_browser' must not appear")
    }

    func testCodeGenCategoryHasPatchFile() {
        let tools = CategoryMapper.getTools(for: .codeGeneration)
        XCTAssertTrue(tools.contains("patch_file"), "codeGeneration must include 'patch_file'")
        XCTAssertFalse(tools.contains("patch_tool"), "Old name 'patch_tool' must not appear")
        XCTAssertTrue(tools.contains("git_action"), "codeGeneration must include 'git_action'")
    }

    func testApplicationAutomationHasRealNames() {
        let tools = CategoryMapper.getTools(for: .applicationAutomation)
        XCTAssertTrue(tools.contains("run_shortcut"), "Must use 'run_shortcut' not 'shortcut_execution'")
        XCTAssertTrue(tools.contains("set_timer"), "Must use 'set_timer' not 'timer_set'")
        XCTAssertFalse(tools.contains("shortcut_execution"), "Old name must not appear")
        XCTAssertFalse(tools.contains("timer_set"), "Old name must not appear")
    }

    // MARK: - Tool Execution

    func testShellToolExecutesCommand() async throws {
        let tool = ShellTool()
        let result = try await tool.execute(params: ["command": AnyCodable("echo hello_elite")], session: session)
        XCTAssertTrue(result.contains("hello_elite"), "Shell tool must return command output")
    }

    func testShellToolBlocksDangerousCommands() async throws {
        let tool = ShellTool()
        // ShellTool blocks destructive patterns by throwing AgentToolError.executionError
        do {
            let result = try await tool.execute(params: ["command": AnyCodable("rm -rf /")], session: session)
            // If it returns (non-throw path), the result must contain a block message
            XCTAssertTrue(result.lowercased().contains("block") || result.lowercased().contains("forbidden") || result.lowercased().contains("denied"),
                          "Shell tool must block 'rm -rf /' with a rejection message")
        } catch AgentToolError.executionError(let msg) {
            XCTAssertTrue(msg.lowercased().contains("block") || msg.lowercased().contains("safety") || msg.lowercased().contains("restrict"),
                          "Thrown error must describe the safety block, got: \(msg)")
        } catch {
            XCTFail("Unexpected error type: \(error)")
        }
    }

    func testReadWriteFileCycle() async throws {
        let writeTool = WriteFileTool()
        let readTool = ReadFileTool()
        let testPath = workspaceURL.appendingPathComponent("test_capability.txt").path
        let content = "EliteAgent capability test content."

        let writeResult = try await writeTool.execute(params: [
            "path": AnyCodable(testPath),
            "content": AnyCodable(content)
        ], session: session)
        XCTAssertTrue(writeResult.lowercased().contains("success") || writeResult.lowercased().contains("write") || writeResult.lowercased().contains("ok") || writeResult.count > 0)

        let readResult = try await readTool.execute(params: ["path": AnyCodable(testPath)], session: session)
        XCTAssertTrue(readResult.contains(content), "Read must return what was written")
    }

    func testSystemInfoToolReturnsData() async throws {
        let tool = SystemInfoTool()
        let result = try await tool.execute(params: [:], session: session)
        XCTAssertTrue(result.contains("macOS") || result.contains("Darwin") || result.contains("Apple"),
                      "SystemInfo must return macOS/hardware data")
    }

    func testSystemTelemetryToolReturnsData() async throws {
        let tool = SystemTelemetryTool()
        let result = try await tool.execute(params: [:], session: session)
        XCTAssertFalse(result.isEmpty, "Telemetry tool must return data")
    }

    func testCalculatorTool() async throws {
        let tool = CalculatorTool()
        let result = try await tool.execute(params: ["expression": AnyCodable("42 * 3")], session: session)
        XCTAssertTrue(result.contains("126"), "Calculator must compute 42*3=126")
    }

    func testGitToolStatus() async throws {
        // Run git status in the EliteAgent repo directory
        let repoSession = Session(workspaceURL: URL(fileURLWithPath: "/Users/trgysvc/Developer/EliteAgent"))
        let tool = GitTool()
        let result = try await tool.execute(params: ["action": AnyCodable("status")], session: repoSession)
        XCTAssertFalse(result.isEmpty, "Git status must return output")
    }

    // MARK: - ANE Classifier

    func testANEClassifierChatIntent() async {
        let category = await ANEInferenceActor.shared.classifyIntent(prompt: "selam nasılsın")
        XCTAssertEqual(category, .chat)
    }

    func testANEClassifierWeatherIntent() async {
        let category = await ANEInferenceActor.shared.classifyIntent(prompt: "istanbul hava durumu")
        XCTAssertEqual(category, .weather)
    }

    func testANEClassifierReturnsOtherForUnknown() async {
        let category = await ANEInferenceActor.shared.classifyIntent(prompt: "please compile this kernel module")
        XCTAssertEqual(category, .other, "Unknown prompts must return .other to fall through to TaskClassifier")
    }
}
