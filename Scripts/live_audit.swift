import Foundation
import EliteAgentCore

@MainActor
func runRealAudit() async {
    print("🚀 GERÇEK DÜNYA DENETİMİ BAŞLADI (No Mocks)")
    print("------------------------------------------")
    
    let session = Session(
        workspaceURL: URL(fileURLWithPath: "/Users/trgysvc/Developer/EliteAgent"),
        config: .default,
        complexity: 1
    )
    
    // 1. Test: System Info
    print("1. [SystemInfoTool] Çalıştırılıyor...")
    let sysInfo = SystemInfoTool()
    do {
        let result = try await sysInfo.execute(params: [:], session: session)
        print("✅ SONUÇ:\n\(result)")
    } catch {
        print("❌ HATA: \(error)")
    }
    
    // 2. Test: Weather (Live)
    print("\n2. [WeatherTool] Çalıştırılıyor (İstanbul)...")
    let weather = WeatherTool()
    do {
        let result = try await weather.execute(params: ["location": AnyCodable("Istanbul")], session: session)
        print("✅ SONUÇ:\n\(result)")
    } catch {
        print("❌ HATA: \(error)")
    }
    
    // 3. Test: Shell (Real Command)
    print("\n3. [ShellTool] Çalıştırılıyor (uname -a)...")
    let shell = ShellTool()
    do {
        let result = try await shell.execute(params: ["command": AnyCodable("uname -a")], session: session)
        print("✅ SONUÇ: \(result)")
    } catch {
        print("❌ HATA: \(error)")
    }
    
    print("\n------------------------------------------")
    print("🏁 DENETİM TAMAMLANDI.")
}

await runRealAudit()
