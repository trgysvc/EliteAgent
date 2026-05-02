import XCTest
import CryptoKit
@testable import EliteAgentCore

final class EliteMarathonTests: XCTestCase {
    
    var tempWorkspace: URL!
    var mockToolRegistry: ToolRegistry!
    var mockVault: VaultManager!
    var bus: SignalBus!
    
    override func setUp() async throws {
        // 1. Setup isolated workspace
        tempWorkspace = FileManager.default.temporaryDirectory.appendingPathComponent("EliteMarathon_\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempWorkspace, withIntermediateDirectories: true)
        
        // 2. Setup mock vault and bus
        let paths = PathConfiguration.shared
        mockVault = try VaultManager(configURL: paths.vaultURL)
        
        let secretData = "ELITE_BUS_SECRET".data(using: .utf8)!
        let busKey = SymmetricKey(data: SHA256.hash(data: secretData))
        bus = SignalBus(secretKey: busKey)
        
        // 3. Tool Registration
        mockToolRegistry = ToolRegistry.shared
        await mockToolRegistry.register(ShellTool())
        await mockToolRegistry.register(GitTool())
        await mockToolRegistry.register(WriteFileTool())
        await mockToolRegistry.register(ReadFileTool())
        await mockToolRegistry.register(PatchTool())
    }
    
    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: tempWorkspace)
    }
    
    // MARK: - Prompt #1: Git Ops (Code Refactoring)
    func testWorkflow1_GitOps_CloneAndPatch() async throws {
        let mockProvider = MockLLMProvider(responses: [
            CompletionResponse(taskID: "t1", providerUsed: .mlx, content: "[UNOB: TASK]", tokensUsed: TokenCount(prompt: 0, completion: 0, total: 0), latencyMs: 0, costUSD: 0),
            CompletionResponse(taskID: "t1", providerUsed: .mlx, content: "<think>I will clone express and patch req.param()</think><final>CALL(32) WITH {\"command\": \"git clone https://github.com/expressjs/express.git .\"}</final>", tokensUsed: TokenCount(prompt: 0, completion: 0, total: 0), latencyMs: 0, costUSD: 0),
            CompletionResponse(taskID: "t1", providerUsed: .mlx, content: "<think>Search for deprecated calls</think><final>CALL(32) WITH {\"command\": \"grep -r 'req.param(' lib/\"}</final>", tokensUsed: TokenCount(prompt: 0, completion: 0, total: 0), latencyMs: 0, costUSD: 0),
            CompletionResponse(taskID: "t1", providerUsed: .mlx, content: "<think>Apply patch</think><final>CALL(41) WITH {\"path\": \"lib/request.js\", \"old_content\": \"req.param(\", \"new_content\": \"req.params[\"}</final>", tokensUsed: TokenCount(prompt: 0, completion: 0, total: 0), latencyMs: 0, costUSD: 0),
            CompletionResponse(taskID: "t1", providerUsed: .mlx, content: "<think>Commit changes</think><final>CALL(42) WITH {\"action\": \"commit\", \"message\": \"Refactor: replace deprecated req.param()\"}</final>", tokensUsed: TokenCount(prompt: 0, completion: 0, total: 0), latencyMs: 0, costUSD: 0),
            CompletionResponse(taskID: "t1", providerUsed: .mlx, content: "<final>DONE: Refactored req.param() to req.params in lib/request.js and committed changes.</final>", tokensUsed: TokenCount(prompt: 0, completion: 0, total: 0), latencyMs: 0, costUSD: 0),
            CompletionResponse(taskID: "t1", providerUsed: .mlx, content: "UNOB:PASS", tokensUsed: TokenCount(prompt: 0, completion: 0, total: 0), latencyMs: 0, costUSD: 0)
        ])
        
        let runtime = OrchestratorRuntime(planner: PlannerAgent(bus: bus), memory: MemoryAgent(bus: bus), cloudProvider: mockProvider, localProvider: nil, toolRegistry: mockToolRegistry, bus: bus, vaultManager: mockVault)
        let session = Session(workspaceURL: tempWorkspace, config: .default, complexity: 4)
        try await runtime.executeTask(prompt: "Clone express repo, replace req.param() with req.params, and commit.", session: session, complexity: 4, config: .default)
        let status = await session.status
        XCTAssertEqual(status, .finished)
    }

    // MARK: - Prompt #2: Web Research & Synthesis
    func testWorkflow2_WebResearch() async throws {
        let mockProvider = MockLLMProvider(responses: [
            CompletionResponse(taskID: "t2", providerUsed: .mlx, content: "[UNOB: RESEARCH]", tokensUsed: TokenCount(prompt: 0, completion: 0, total: 0), latencyMs: 0, costUSD: 0),
            CompletionResponse(taskID: "t2", providerUsed: .mlx, content: "<think>Searching papers</think><final>CALL(45) WITH {\"query\": \"Distillation of Large Language Models latest papers\"}</final>", tokensUsed: TokenCount(prompt: 0, completion: 0, total: 0), latencyMs: 0, costUSD: 0),
            CompletionResponse(taskID: "t2", providerUsed: .mlx, content: "<think>Reading PDF 1</think><final>CALL(32) WITH {\"command\": \"curl -O paper1_url\"}</final>", tokensUsed: TokenCount(prompt: 0, completion: 0, total: 0), latencyMs: 0, costUSD: 0),
            CompletionResponse(taskID: "t2", providerUsed: .mlx, content: "<think>Reading PDF 2</think><final>CALL(32) WITH {\"command\": \"curl -O paper2_url\"}</final>", tokensUsed: TokenCount(prompt: 0, completion: 0, total: 0), latencyMs: 0, costUSD: 0),
            CompletionResponse(taskID: "t2", providerUsed: .mlx, content: "<think>Reading PDF 3</think><final>CALL(32) WITH {\"command\": \"curl -O paper3_url\"}</final>", tokensUsed: TokenCount(prompt: 0, completion: 0, total: 0), latencyMs: 0, costUSD: 0),
            CompletionResponse(taskID: "t2", providerUsed: .mlx, content: "<think>Writing report</think><final>CALL(34) WITH {\"path\": \"llm_distillation_comparison.md\", \"content\": \"| Paper | Summary |\\n|---|---|...\"}</final>", tokensUsed: TokenCount(prompt: 0, completion: 0, total: 0), latencyMs: 0, costUSD: 0),
            CompletionResponse(taskID: "t2", providerUsed: .mlx, content: "<final>DONE: Researched LLM distillation papers and generated the comparison report.</final>", tokensUsed: TokenCount(prompt: 0, completion: 0, total: 0), latencyMs: 0, costUSD: 0),
            CompletionResponse(taskID: "t2", providerUsed: .mlx, content: "UNOB:PASS", tokensUsed: TokenCount(prompt: 0, completion: 0, total: 0), latencyMs: 0, costUSD: 0)
        ])
        
        let runtime = OrchestratorRuntime(planner: PlannerAgent(bus: bus), memory: MemoryAgent(bus: bus), cloudProvider: mockProvider, localProvider: nil, toolRegistry: mockToolRegistry, bus: bus, vaultManager: mockVault)
        let session = Session(workspaceURL: tempWorkspace, config: .default, complexity: 4)
        try await runtime.executeTask(prompt: "Search for LLM distillation papers, summarize top 3, and create comparison table.", session: session, complexity: 4, config: .default)
        let status = await session.status
        XCTAssertEqual(status, .finished)
    }

    // MARK: - Prompt #3: Monitoring & Alerting
    func testWorkflow3_MonitoringAlerting() async throws {
        let mockProvider = MockLLMProvider(responses: [
            CompletionResponse(taskID: "t3", providerUsed: .mlx, content: "[UNOB: TASK]", tokensUsed: TokenCount(prompt: 0, completion: 0, total: 0), latencyMs: 0, costUSD: 0),
            CompletionResponse(taskID: "t3", providerUsed: .mlx, content: "<think>Check memory</think><final>CALL(32) WITH {\"command\": \"vm_stat\"}</final>", tokensUsed: TokenCount(prompt: 0, completion: 0, total: 0), latencyMs: 0, costUSD: 0),
            CompletionResponse(taskID: "t3", providerUsed: .mlx, content: "<think>Memory OK. Log and wait.</think><final>CALL(34) WITH {\"path\": \"sys_monitor_log.md\", \"content\": \"Reading 1: 45%\"}</final>", tokensUsed: TokenCount(prompt: 0, completion: 0, total: 0), latencyMs: 0, costUSD: 0),
            CompletionResponse(taskID: "t3", providerUsed: .mlx, content: "<final>DONE: System memory monitor log created.</final>", tokensUsed: TokenCount(prompt: 0, completion: 0, total: 0), latencyMs: 0, costUSD: 0),
            CompletionResponse(taskID: "t3", providerUsed: .mlx, content: "UNOB:PASS", tokensUsed: TokenCount(prompt: 0, completion: 0, total: 0), latencyMs: 0, costUSD: 0)
        ])
        
        let runtime = OrchestratorRuntime(planner: PlannerAgent(bus: bus), memory: MemoryAgent(bus: bus), cloudProvider: mockProvider, localProvider: nil, toolRegistry: mockToolRegistry, bus: bus, vaultManager: mockVault)
        let session = Session(workspaceURL: tempWorkspace, config: .default, complexity: 4)
        try await runtime.executeTask(prompt: "Monitor memory every 5 mins for 30 mins, alert if >85%.", session: session, complexity: 4, config: .default)
        let status = await session.status
        XCTAssertEqual(status, .finished)
    }

    // MARK: - Prompt #4: 3D Scene Automation
    func testWorkflow4_BlenderAutomation() async throws {
        let mockProvider = MockLLMProvider(responses: [
            CompletionResponse(taskID: "t4", providerUsed: .mlx, content: "[UNOB: CREATIVE3D]", tokensUsed: TokenCount(prompt: 0, completion: 0, total: 0), latencyMs: 0, costUSD: 0),
            CompletionResponse(taskID: "t4", providerUsed: .mlx, content: "<think>Generate Blender script</think><final>CALL(60) WITH {\"action\": \"execute_script\", \"script\": \"import bpy...\"}</final>", tokensUsed: TokenCount(prompt: 0, completion: 0, total: 0), latencyMs: 0, costUSD: 0),
            CompletionResponse(taskID: "t4", providerUsed: .mlx, content: "<think>Render scene</think><final>CALL(60) WITH {\"action\": \"render\", \"path\": \"city_render.png\"}</final>", tokensUsed: TokenCount(prompt: 0, completion: 0, total: 0), latencyMs: 0, costUSD: 0),
            CompletionResponse(taskID: "t4", providerUsed: .mlx, content: "<final>DONE: Blender scene rendered successfully.</final>", tokensUsed: TokenCount(prompt: 0, completion: 0, total: 0), latencyMs: 0, costUSD: 0),
            CompletionResponse(taskID: "t4", providerUsed: .mlx, content: "UNOB:PASS", tokensUsed: TokenCount(prompt: 0, completion: 0, total: 0), latencyMs: 0, costUSD: 0)
        ])
        
        let runtime = OrchestratorRuntime(planner: PlannerAgent(bus: bus), memory: MemoryAgent(bus: bus), cloudProvider: mockProvider, localProvider: nil, toolRegistry: mockToolRegistry, bus: bus, vaultManager: mockVault)
        let session = Session(workspaceURL: tempWorkspace, config: .default, complexity: 4)
        try await runtime.executeTask(prompt: "Create a procedural city in Blender and render it.", session: session, complexity: 4, config: .default)
        let status = await session.status
        XCTAssertEqual(status, .finished)
    }

    // MARK: - Prompt #5: TDD Loop (DataParser)
    func testWorkflow5_ProjectBootstrappingAndTDD() async throws {
        let mockProvider = MockLLMProvider(responses: [
            CompletionResponse(taskID: "t5", providerUsed: .mlx, content: "[UNOB: TASK]", tokensUsed: TokenCount(prompt: 0, completion: 0, total: 0), latencyMs: 0, costUSD: 0),
            CompletionResponse(taskID: "t5", providerUsed: .mlx, content: "<think>Init package</think><final>CALL(32) WITH {\"command\": \"swift package init --type executable\"}</final>", tokensUsed: TokenCount(prompt: 0, completion: 0, total: 0), latencyMs: 0, costUSD: 0),
            CompletionResponse(taskID: "t5", providerUsed: .mlx, content: "<think>Write implementation</think><final>CALL(34) WITH {\"path\": \"Sources/main.swift\", \"content\": \"func parse() { }\"}</final>", tokensUsed: TokenCount(prompt: 0, completion: 0, total: 0), latencyMs: 0, costUSD: 0),
            CompletionResponse(taskID: "t5", providerUsed: .mlx, content: "<think>Write tests</think><final>CALL(34) WITH {\"path\": \"Tests/DataParserTests.swift\", \"content\": \"import XCTest...\"}</final>", tokensUsed: TokenCount(prompt: 0, completion: 0, total: 0), latencyMs: 0, costUSD: 0),
            CompletionResponse(taskID: "t5", providerUsed: .mlx, content: "<think>Run tests</think><final>CALL(32) WITH {\"command\": \"swift test\"}</final>", tokensUsed: TokenCount(prompt: 0, completion: 0, total: 0), latencyMs: 0, costUSD: 0),
            CompletionResponse(taskID: "t5", providerUsed: .mlx, content: "<think>Tests failed. Fixing logic.</think><final>CALL(41) WITH {\"path\": \"Sources/main.swift\", \"old_content\": \"func parse() { }\", \"new_content\": \"func parse() { /* real logic */ }\"}</final>", tokensUsed: TokenCount(prompt: 0, completion: 0, total: 0), latencyMs: 0, costUSD: 0),
            CompletionResponse(taskID: "t5", providerUsed: .mlx, content: "<think>Verify fix</think><final>CALL(32) WITH {\"command\": \"swift test\"}</final>", tokensUsed: TokenCount(prompt: 0, completion: 0, total: 0), latencyMs: 0, costUSD: 0),
            CompletionResponse(taskID: "t5", providerUsed: .mlx, content: "<final>DONE: Package initialized, implemented, and verified with tests.</final>", tokensUsed: TokenCount(prompt: 0, completion: 0, total: 0), latencyMs: 0, costUSD: 0),
            CompletionResponse(taskID: "t5", providerUsed: .mlx, content: "UNOB:PASS", tokensUsed: TokenCount(prompt: 0, completion: 0, total: 0), latencyMs: 0, costUSD: 0)
        ])
        
        let runtime = OrchestratorRuntime(planner: PlannerAgent(bus: bus), memory: MemoryAgent(bus: bus), cloudProvider: mockProvider, localProvider: nil, toolRegistry: mockToolRegistry, bus: bus, vaultManager: mockVault)
        let session = Session(workspaceURL: tempWorkspace, config: .default, complexity: 4)
        try await runtime.executeTask(prompt: "Create DataParser Swift package, implement CSV parsing with tests, and ensure tests pass.", session: session, complexity: 4, config: .default)
        let status = await session.status
        XCTAssertEqual(status, .finished)
    }

    // MARK: - Prompt #6: System Configuration & Port Management
    func testWorkflow6_SystemConfigPortManagement() async throws {
        let mockProvider = MockLLMProvider(responses: [
            CompletionResponse(taskID: "t6", providerUsed: .mlx, content: "[UNOB: TASK]", tokensUsed: TokenCount(prompt: 0, completion: 0, total: 0), latencyMs: 0, costUSD: 0),
            CompletionResponse(taskID: "t6", providerUsed: .mlx, content: "<think>Check Docker</think><final>CALL(32) WITH {\"command\": \"docker --version\"}</final>", tokensUsed: TokenCount(prompt: 0, completion: 0, total: 0), latencyMs: 0, costUSD: 0),
            CompletionResponse(taskID: "t6", providerUsed: .mlx, content: "<think>Check port 8080</think><final>CALL(32) WITH {\"command\": \"lsof -i :8080\"}</final>", tokensUsed: TokenCount(prompt: 0, completion: 0, total: 0), latencyMs: 0, costUSD: 0),
            CompletionResponse(taskID: "t6", providerUsed: .mlx, content: "<think>8080 in use. Using 8081.</think><final>CALL(32) WITH {\"command\": \"docker run -d -p 8081:80 nginx\"}</final>", tokensUsed: TokenCount(prompt: 0, completion: 0, total: 0), latencyMs: 0, costUSD: 0),
            CompletionResponse(taskID: "t6", providerUsed: .mlx, content: "<final>DONE: Nginx container started on port 8081.</final>", tokensUsed: TokenCount(prompt: 0, completion: 0, total: 0), latencyMs: 0, costUSD: 0),
            CompletionResponse(taskID: "t6", providerUsed: .mlx, content: "UNOB:PASS", tokensUsed: TokenCount(prompt: 0, completion: 0, total: 0), latencyMs: 0, costUSD: 0)
        ])
        
        let runtime = OrchestratorRuntime(planner: PlannerAgent(bus: bus), memory: MemoryAgent(bus: bus), cloudProvider: mockProvider, localProvider: nil, toolRegistry: mockToolRegistry, bus: bus, vaultManager: mockVault)
        let session = Session(workspaceURL: tempWorkspace, config: .default, complexity: 4)
        try await runtime.executeTask(prompt: "Start Nginx in Docker on 8080, fallback if port in use.", session: session, complexity: 4, config: .default)
        let status = await session.status
        XCTAssertEqual(status, .finished)
    }

    // MARK: - Prompt #7: Cross-Reference Documentation
    func testWorkflow7_CrossReferenceDocs() async throws {
        let mockProvider = MockLLMProvider(responses: [
            CompletionResponse(taskID: "t7", providerUsed: .mlx, content: "[UNOB: TASK]", tokensUsed: TokenCount(prompt: 0, completion: 0, total: 0), latencyMs: 0, costUSD: 0),
            CompletionResponse(taskID: "t7", providerUsed: .mlx, content: "<think>Read README</think><final>CALL(33) WITH {\"path\": \"README.md\"}</final>", tokensUsed: TokenCount(prompt: 0, completion: 0, total: 0), latencyMs: 0, costUSD: 0),
            CompletionResponse(taskID: "t7", providerUsed: .mlx, content: "<think>List core files</think><final>CALL(32) WITH {\"command\": \"find Sources/EliteAgentCore -maxdepth 2\"}</final>", tokensUsed: TokenCount(prompt: 0, completion: 0, total: 0), latencyMs: 0, costUSD: 0),
            CompletionResponse(taskID: "t7", providerUsed: .mlx, content: "<think>Analyze gaps</think><final>CALL(34) WITH {\"path\": \"architecture_gap_analysis.md\", \"content\": \"Gap analysis result...\"}</final>", tokensUsed: TokenCount(prompt: 0, completion: 0, total: 0), latencyMs: 0, costUSD: 0),
            CompletionResponse(taskID: "t7", providerUsed: .mlx, content: "<final>DONE: Architecture gap analysis report generated.</final>", tokensUsed: TokenCount(prompt: 0, completion: 0, total: 0), latencyMs: 0, costUSD: 0),
            CompletionResponse(taskID: "t7", providerUsed: .mlx, content: "UNOB:PASS", tokensUsed: TokenCount(prompt: 0, completion: 0, total: 0), latencyMs: 0, costUSD: 0)
        ])
        
        let runtime = OrchestratorRuntime(planner: PlannerAgent(bus: bus), memory: MemoryAgent(bus: bus), cloudProvider: mockProvider, localProvider: nil, toolRegistry: mockToolRegistry, bus: bus, vaultManager: mockVault)
        let session = Session(workspaceURL: tempWorkspace, config: .default, complexity: 4)
        try await runtime.executeTask(prompt: "Perform gap analysis between README and actual core code.", session: session, complexity: 4, config: .default)
        let status = await session.status
        XCTAssertEqual(status, .finished)
    }

    // MARK: - Prompt #8: Legacy Code Migration
    func testWorkflow8_LegacyCodeMigration() async throws {
        let mockProvider = MockLLMProvider(responses: [
            CompletionResponse(taskID: "t8", providerUsed: .mlx, content: "[UNOB: TASK]", tokensUsed: TokenCount(prompt: 0, completion: 0, total: 0), latencyMs: 0, costUSD: 0),
            CompletionResponse(taskID: "t8", providerUsed: .mlx, content: "<think>Find Python files</think><final>CALL(32) WITH {\"command\": \"find scripts/legacy -name '*.py'\"}</final>", tokensUsed: TokenCount(prompt: 0, completion: 0, total: 0), latencyMs: 0, costUSD: 0),
            CompletionResponse(taskID: "t8", providerUsed: .mlx, content: "<think>Patch print statements</think><final>CALL(41) WITH {\"path\": \"scripts/legacy/old.py\", \"old_content\": \"print 'hello'\", \"new_content\": \"print('hello')\"}</final>", tokensUsed: TokenCount(prompt: 0, completion: 0, total: 0), latencyMs: 0, costUSD: 0),
            CompletionResponse(taskID: "t8", providerUsed: .mlx, content: "<think>Run flake8</think><final>CALL(32) WITH {\"command\": \"flake8 scripts/legacy/old.py\"}</final>", tokensUsed: TokenCount(prompt: 0, completion: 0, total: 0), latencyMs: 0, costUSD: 0),
            CompletionResponse(taskID: "t8", providerUsed: .mlx, content: "<final>DONE: Legacy Python scripts migrated to Python 3.</final>", tokensUsed: TokenCount(prompt: 0, completion: 0, total: 0), latencyMs: 0, costUSD: 0),
            CompletionResponse(taskID: "t8", providerUsed: .mlx, content: "UNOB:PASS", tokensUsed: TokenCount(prompt: 0, completion: 0, total: 0), latencyMs: 0, costUSD: 0)
        ])
        
        let runtime = OrchestratorRuntime(planner: PlannerAgent(bus: bus), memory: MemoryAgent(bus: bus), cloudProvider: mockProvider, localProvider: nil, toolRegistry: mockToolRegistry, bus: bus, vaultManager: mockVault)
        let session = Session(workspaceURL: tempWorkspace, config: .default, complexity: 4)
        try await runtime.executeTask(prompt: "Convert Python 2 print to Python 3 in legacy scripts and verify with flake8.", session: session, complexity: 4, config: .default)
        let status = await session.status
        XCTAssertEqual(status, .finished)
    }

    // MARK: - Prompt #9: Data Extraction Plist
    func testWorkflow9_DataExtractionPlist() async throws {
        let mockProvider = MockLLMProvider(responses: [
            CompletionResponse(taskID: "t9", providerUsed: .mlx, content: "[UNOB: TASK]", tokensUsed: TokenCount(prompt: 0, completion: 0, total: 0), latencyMs: 0, costUSD: 0),
            CompletionResponse(taskID: "t9", providerUsed: .mlx, content: "<think>Download data</think><final>CALL(32) WITH {\"command\": \"curl -o data.csv url\"}</final>", tokensUsed: TokenCount(prompt: 0, completion: 0, total: 0), latencyMs: 0, costUSD: 0),
            CompletionResponse(taskID: "t9", providerUsed: .mlx, content: "<think>Convert to Plist</think><final>CALL(32) WITH {\"command\": \"python3 -c \\\"import plistlib...\\\"\"}</final>", tokensUsed: TokenCount(prompt: 0, completion: 0, total: 0), latencyMs: 0, costUSD: 0),
            CompletionResponse(taskID: "t9", providerUsed: .mlx, content: "<final>DONE: Weather data converted to binary plist.</final>", tokensUsed: TokenCount(prompt: 0, completion: 0, total: 0), latencyMs: 0, costUSD: 0),
            CompletionResponse(taskID: "t9", providerUsed: .mlx, content: "UNOB:PASS", tokensUsed: TokenCount(prompt: 0, completion: 0, total: 0), latencyMs: 0, costUSD: 0)
        ])
        
        let runtime = OrchestratorRuntime(planner: PlannerAgent(bus: bus), memory: MemoryAgent(bus: bus), cloudProvider: mockProvider, localProvider: nil, toolRegistry: mockToolRegistry, bus: bus, vaultManager: mockVault)
        let session = Session(workspaceURL: tempWorkspace, config: .default, complexity: 4)
        try await runtime.executeTask(prompt: "Fetch weather data and save it as a binary plist.", session: session, complexity: 4, config: .default)
        let status = await session.status
        XCTAssertEqual(status, .finished)
    }

    // MARK: - Prompt #10: Complex Build Debugging
    func testWorkflow10_ComplexBuildDebugging() async throws {
        let mockProvider = MockLLMProvider(responses: [
            CompletionResponse(taskID: "t10", providerUsed: .mlx, content: "[UNOB: TASK]", tokensUsed: TokenCount(prompt: 0, completion: 0, total: 0), latencyMs: 0, costUSD: 0),
            CompletionResponse(taskID: "t10", providerUsed: .mlx, content: "<think>Run build</think><final>CALL(32) WITH {\"command\": \"xcodebuild\"}</final>", tokensUsed: TokenCount(prompt: 0, completion: 0, total: 0), latencyMs: 0, costUSD: 0),
            CompletionResponse(taskID: "t10", providerUsed: .mlx, content: "<think>Build failed. Analyze Package.swift</think><final>CALL(33) WITH {\"path\": \"Package.swift\"}</final>", tokensUsed: TokenCount(prompt: 0, completion: 0, total: 0), latencyMs: 0, costUSD: 0),
            CompletionResponse(taskID: "t10", providerUsed: .mlx, content: "<think>Fix dependency cycle</think><final>CALL(41) WITH {\"path\": \"Package.swift\", \"old_content\": \"...\", \"new_content\": \"...\"}</final>", tokensUsed: TokenCount(prompt: 0, completion: 0, total: 0), latencyMs: 0, costUSD: 0),
            CompletionResponse(taskID: "t10", providerUsed: .mlx, content: "<think>Retry build</think><final>CALL(32) WITH {\"command\": \"xcodebuild\"}</final>", tokensUsed: TokenCount(prompt: 0, completion: 0, total: 0), latencyMs: 0, costUSD: 0),
            CompletionResponse(taskID: "t10", providerUsed: .mlx, content: "<final>DONE: Cyclic dependency fixed in Package.swift.</final>", tokensUsed: TokenCount(prompt: 0, completion: 0, total: 0), latencyMs: 0, costUSD: 0),
            CompletionResponse(taskID: "t10", providerUsed: .mlx, content: "UNOB:PASS", tokensUsed: TokenCount(prompt: 0, completion: 0, total: 0), latencyMs: 0, costUSD: 0)
        ])
        
        let runtime = OrchestratorRuntime(planner: PlannerAgent(bus: bus), memory: MemoryAgent(bus: bus), cloudProvider: mockProvider, localProvider: nil, toolRegistry: mockToolRegistry, bus: bus, vaultManager: mockVault)
        let session = Session(workspaceURL: tempWorkspace, config: .default, complexity: 4)
        try await runtime.executeTask(prompt: "Fix the cyclic dependency in the Xcode build.", session: session, complexity: 4, config: .default)
        let status = await session.status
        XCTAssertEqual(status, .finished)
    }

    // MARK: - Prompt #11: Ecosystem Integration (Calendar & Contacts)
    func testWorkflow11_EcosystemIntegration() async throws {
        let mockProvider = MockLLMProvider(responses: [
            CompletionResponse(taskID: "t11", providerUsed: .mlx, content: "[UNOB: TASK]", tokensUsed: TokenCount(prompt: 0, completion: 0, total: 0), latencyMs: 0, costUSD: 0),
            CompletionResponse(taskID: "t11", providerUsed: .mlx, content: "<think>Find contact</think><final>CALL(39) WITH {\"query\": \"John Doe\"}</final>", tokensUsed: TokenCount(prompt: 0, completion: 0, total: 0), latencyMs: 0, costUSD: 0),
            CompletionResponse(taskID: "t11", providerUsed: .mlx, content: "<think>Schedule meeting</think><final>CALL(54) WITH {\"action\": \"add_event\", \"summary\": \"Meeting with John\", \"start\": \"tomorrow 2pm\"}</final>", tokensUsed: TokenCount(prompt: 0, completion: 0, total: 0), latencyMs: 0, costUSD: 0),
            CompletionResponse(taskID: "t11", providerUsed: .mlx, content: "<final>DONE: Meeting scheduled with John Doe.</final>", tokensUsed: TokenCount(prompt: 0, completion: 0, total: 0), latencyMs: 0, costUSD: 0),
            CompletionResponse(taskID: "t11", providerUsed: .mlx, content: "UNOB:PASS", tokensUsed: TokenCount(prompt: 0, completion: 0, total: 0), latencyMs: 0, costUSD: 0)
        ])
        
        let runtime = OrchestratorRuntime(planner: PlannerAgent(bus: bus), memory: MemoryAgent(bus: bus), cloudProvider: mockProvider, localProvider: nil, toolRegistry: mockToolRegistry, bus: bus, vaultManager: mockVault)
        let session = Session(workspaceURL: tempWorkspace, config: .default, complexity: 3)
        try await runtime.executeTask(prompt: "Find John Doe in contacts and schedule a meeting with him tomorrow at 2pm.", session: session, complexity: 3, config: .default)
        let status = await session.status
        XCTAssertEqual(status, .finished)
    }

    // MARK: - Prompt #12: System Health & Telemetry
    func testWorkflow12_SystemHealthCheck() async throws {
        let mockProvider = MockLLMProvider(responses: [
            CompletionResponse(taskID: "t12", providerUsed: .mlx, content: "[UNOB: TASK]", tokensUsed: TokenCount(prompt: 0, completion: 0, total: 0), latencyMs: 0, costUSD: 0),
            CompletionResponse(taskID: "t12", providerUsed: .mlx, content: "<think>Check telemetry</think><final>CALL(36) WITH {}</final>", tokensUsed: TokenCount(prompt: 0, completion: 0, total: 0), latencyMs: 0, costUSD: 0),
            CompletionResponse(taskID: "t12", providerUsed: .mlx, content: "<think>Check disk space</think><final>CALL(32) WITH {\"command\": \"df -h /\"}</final>", tokensUsed: TokenCount(prompt: 0, completion: 0, total: 0), latencyMs: 0, costUSD: 0),
            CompletionResponse(taskID: "t12", providerUsed: .mlx, content: "<final>DONE: System health check complete. Disk space and telemetry are within nominal limits.</final>", tokensUsed: TokenCount(prompt: 0, completion: 0, total: 0), latencyMs: 0, costUSD: 0),
            CompletionResponse(taskID: "t12", providerUsed: .mlx, content: "UNOB:PASS", tokensUsed: TokenCount(prompt: 0, completion: 0, total: 0), latencyMs: 0, costUSD: 0)
        ])
        
        let runtime = OrchestratorRuntime(planner: PlannerAgent(bus: bus), memory: MemoryAgent(bus: bus), cloudProvider: mockProvider, localProvider: nil, toolRegistry: mockToolRegistry, bus: bus, vaultManager: mockVault)
        let session = Session(workspaceURL: tempWorkspace, config: .default, complexity: 3)
        try await runtime.executeTask(prompt: "Perform a system health check including telemetry and disk space.", session: session, complexity: 3, config: .default)
        let status = await session.status
        XCTAssertEqual(status, .finished)
    }
}

// MARK: - Test Mocks

actor MockLLMProvider: LLMProvider {
    let providerID: ProviderID = .mlx
    let providerType: ProviderType = .local
    var capabilities: Set<Capability> = [.general, .code]
    var costPer1KTokens: Decimal = 0
    var maxContextTokens: Int = 8192
    var status: ProviderStatus = .ready
    let isLoaded: Bool = true
    
    var responses: [CompletionResponse]
    
    init(responses: [CompletionResponse] = []) {
        self.responses = responses
    }
    
    func healthCheck() async -> Bool { return true }
    
    func complete(_ request: CompletionRequest, useSafeMode: Bool) async throws -> CompletionResponse {
        guard !responses.isEmpty else {
            return CompletionResponse(taskID: "done", providerUsed: .mlx, content: "DONE", tokensUsed: TokenCount(prompt: 0, completion: 0, total: 0), latencyMs: 0, costUSD: 0)
        }
        return responses.removeFirst()
    }
}
