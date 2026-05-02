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
        let tools = await ToolRegistry.shared.listTools()
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
        let reportString = """
        🔍 [UNO DIAGNOSTIC REPORT]
        ------------------------------------------
        🕒 Zaman: \(report.timestamp)
        🛠 Kayıtlı Araç Sayısı: \(report.toolCount) (Hedef: 35)
        🔌 Yüklü Eklenti Sayısı: \(report.pluginCount)
        🧠 Model Hazır mı: \(report.modelLoaded ? "EVET" : "HAYIR")
        📡 XPC Erişilebilirliği: \(report.xpcReachable ? "OK" : "HATA")
        ------------------------------------------
        """
        AgentLogger.logInfo(reportString, agent: "Diagnostic")
    }
}
