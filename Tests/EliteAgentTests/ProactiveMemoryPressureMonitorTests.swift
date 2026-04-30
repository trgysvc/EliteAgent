import XCTest
@testable import EliteAgentCore

final class ProactiveMemoryPressureMonitorTests: XCTestCase {

    func testMonitorInstantiation() {
        // Verify that ProactiveMemoryPressureMonitor can be instantiated
        let monitor = ProactiveMemoryPressureMonitor.shared
        XCTAssertNotNil(monitor, "Monitor should be instantiated as a singleton")
    }

    func testStartMonitoringDoesNotCrash() async throws {
        // Verify that startMonitoring() executes without crashing
        let monitor = ProactiveMemoryPressureMonitor.shared

        // This should complete without throwing
        await monitor.startMonitoring()

        // Give it a moment to initialize
        try await Task.sleep(nanoseconds: 100_000_000) // 100ms

        XCTAssertTrue(true, "startMonitoring() completed without crashing")
    }

    func testOrchestratorRuntimeMethods() async throws {
        // Verify that OrchestratorRuntime pause/resume/triggerCompaction methods are callable

        // pauseAllSessions should be callable (static method)
        OrchestratorRuntime.pauseAllSessions()
        XCTAssertTrue(true, "pauseAllSessions() is callable")

        // resumeAllSessions should be callable (static method)
        OrchestratorRuntime.resumeAllSessions()
        XCTAssertTrue(true, "resumeAllSessions() is callable")

        // triggerCompaction should be callable and not crash
        OrchestratorRuntime.triggerCompaction()

        // Give async Task time to execute
        try await Task.sleep(nanoseconds: 100_000_000) // 100ms

        XCTAssertTrue(true, "triggerCompaction() completed without crashing")
    }
}
