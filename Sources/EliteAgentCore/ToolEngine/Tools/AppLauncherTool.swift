import AppKit
import Foundation

public struct AppLauncherTool: AgentTool, Sendable {
    public let name = "app_launcher"
    public let summary = "Natively launch macOS applications (Safe & Sandbox-friendly)."
    public let description = "Use this to open any macOS application by name. This is safer than shell commands. Parameter: app_name (string)."
    public let ubid: Int128 = 88
    
    public init() {}
    
    public func execute(params: [String: AnyCodable], session: Session) async throws(AgentToolError) -> String {
        guard let appName = params["app_name"]?.value as? String else {
            throw AgentToolError.missingParameter("'app_name' parameter is required.")
        }
        
        let workspace = NSWorkspace.shared
        
        // Try to find the app URL
        if let appURL = workspace.urlForApplication(withBundleIdentifier: appName) ?? workspace.urlForApplication(withBundleIdentifier: "com.apple.\(appName.lowercased())") {
            let config = NSWorkspace.OpenConfiguration()
            do {
                try await workspace.openApplication(at: appURL, configuration: config)
                return "SUCCESS: \(appName) başlatıldı."
            } catch {
                return "FAIL: \(appName) başlatılamadı. Hata: \(error.localizedDescription)"
            }
        }
        
        // Fallback: Try searching by name if Bundle ID fails
        let searchPath = "/Applications"
        let fm = FileManager.default
        let apps = (try? fm.contentsOfDirectory(atPath: searchPath)) ?? []
        
        if let foundApp = apps.first(where: { $0.lowercased().contains(appName.lowercased()) }) {
            let appURL = URL(fileURLWithPath: searchPath).appendingPathComponent(foundApp)
            let config = NSWorkspace.OpenConfiguration()
            do {
                try await workspace.openApplication(at: appURL, configuration: config)
                return "SUCCESS: \(appName) (\(foundApp)) başlatıldı."
            } catch {
                return "FAIL: \(appName) başlatılamadı. Hata: \(error.localizedDescription)"
            }
        }
        
        return "HATA: '\(appName)' isimli uygulama bulunamadı."
    }
}
