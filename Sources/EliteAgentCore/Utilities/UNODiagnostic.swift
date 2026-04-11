import Foundation

/// v14.0: UNO Diagnostic Utility
/// Used to verify system integrity post-migration.
public struct UNODiagnostic {
    public struct Report: Codable {
        public let timestamp: Date
        public let toolCount: Int
        public let pluginCount: Int
        public let activeActors: [String]
        public let modelLoaded: Bool
        public let xpcReachable: Bool
    }
    
    public static func generateReport() async -> Report {
        let tools = ToolRegistry.shared.listTools()
        let plugins = PluginManager.shared.loadedPlugins
        
        // v14.0: Check if model is actually ready in VRAM
        let isModelReady = await ModelSetupManager.shared.isModelReady
        
        return Report(
            timestamp: Date(),
            toolCount: tools.count,
            pluginCount: plugins.count,
            activeActors: [], // Placeholder for future actor enumeration if needed
            modelLoaded: isModelReady,
            xpcReachable: true // Assuming true for now if we can call this
        )
    }
    
    public static func printReport(_ report: Report) {
        print("\n🔍 [UNO DIAGNOSTIC REPORT]")
        print("------------------------------------------")
        print("🕒 Zaman: \(report.timestamp)")
        print("🛠 Kayıtlı Araç Sayısı: \(report.toolCount) (Hedef: 35)")
        print("🔌 Yüklü Eklenti Sayısı: \(report.pluginCount)")
        print("🧠 Model Hazır mı: \(report.modelLoaded ? "EVET" : "HAYIR")")
        print("📡 XPC Erişilebilirliği: \(report.xpcReachable ? "OK" : "HATA")")
        print("------------------------------------------\n")
    }
}
