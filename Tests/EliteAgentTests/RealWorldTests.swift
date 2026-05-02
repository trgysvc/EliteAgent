import XCTest
@testable import EliteAgentCore

final class RealWorldTests: XCTestCase {
    func testRealWorldTools() async throws {
        print("\n🚀 --- GERÇEK DÜNYA TESTİ BAŞLIYOR ---")
        
        let session = Session(
            workspaceURL: URL(fileURLWithPath: "/Users/trgysvc/Developer/EliteAgent"),
            config: .default,
            complexity: 1
        )
        
        // 1. System Info
        let sysInfo = SystemInfoTool()
        let sysResult = try await sysInfo.execute(params: [:], session: session)
        print("\n[SYSTEM INFO]:\n\(sysResult)")
        XCTAssertTrue(sysResult.contains("macOS"))
        
        // 2. Shell
        let shell = ShellTool()
        let shellResult = try await shell.execute(params: ["command": AnyCodable("uname -m")], session: session)
        print("\n[SHELL (uname -m)]: \(shellResult)")
        XCTAssertTrue(shellResult.contains("arm64"))
        
        // 3. Weather
        let weather = WeatherTool()
        do {
            let weatherResult = try await weather.execute(params: ["location": AnyCodable("Istanbul")], session: session)
            print("\n[WEATHER (Istanbul)]:\n\(weatherResult)")
            XCTAssertTrue(weatherResult.contains("İstanbul") || weatherResult.contains("Istanbul"))
        } catch {
            print("\n[WEATHER] Skipped or Failed (Check Network): \(error)")
        }
        
        print("\n🚀 --- GERÇEK DÜNYA TESTİ TAMAMLANDI ---\n")
    }
}
