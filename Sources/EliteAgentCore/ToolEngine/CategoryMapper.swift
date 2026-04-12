import Foundation

/// CategoryMapper: Görev kategorisine göre en uygun araç setini belirleyen rehber.
/// Bu sayede modele sadece ihtiyacı olan araçlar sunularak token tasarrufu ve kararlılık sağlanır.
public struct CategoryMapper {
    
    /// Her kategori için 'olmazsa olmaz' (core) araçları tanımlar.
    /// Not: shell_exec ve memory her zaman global olarak eklenecektir.
    private static let categoryMap: [TaskCategory: [String]] = [
        .research: ["google_search", "web_search", "web_fetch", "native_browser", "safari_automation"],
        .applicationAutomation: ["media_control", "apple_calendar", "apple_mail", "shortcut_execution", "discover_shortcuts", "send_message_via_whatsapp_or_imessage"],
        .systemManagement: ["get_system_telemetry", "app_discovery", "process_manager", "system_status", "discover_shortcuts", "run_shortcut"],
        .fileProcessing: ["read_file", "write_file", "path_tool", "file_manager", "patch_tool"],
        .codeGeneration: ["read_file", "write_file", "shell_exec", "git_action", "patch_tool"],
        .hardware: ["get_system_telemetry", "get_system_info", "system_status"],
        .weather: ["get_weather", "google_search", "send_message_via_whatsapp_or_imessage"],
        .conversation: ["memory", "send_message_via_whatsapp_or_imessage", "email"],
        .chat: ["memory"]
    ]
    
    /// Evrensel olarak her zaman görünür olması gereken emniyet araçları.
    public static let globalTools = ["shell_exec", "memory"]

    public static func getTools(for category: TaskCategory) -> [String] {
        var tools = categoryMap[category] ?? []
        // Global araçları ekle (duplikasyon kontrolüyle)
        for tool in globalTools {
            if !tools.contains(tool) {
                tools.append(tool)
            }
        }
        return tools
    }
}
