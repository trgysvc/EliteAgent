import Foundation

/// CategoryMapper: Görev kategorisine göre en uygun araç setini belirleyen rehber.
/// Bu sayede modele sadece ihtiyacı olan araçlar sunularak token tasarrufu ve kararlılık sağlanır.
public struct CategoryMapper {
    
    /// Her kategori için 'olmazsa olmaz' (core) araçları tanımlar.
    /// Not: shell_exec ve memory her zaman global olarak eklenecektir.
    private static let categoryMap: [TaskCategory: [String]] = [
        .research: ["web_search", "web_fetch", "browser_native", "safari_automation"],
        .applicationAutomation: ["media_control", "apple_calendar", "apple_mail", "run_shortcut", "discover_shortcuts", "send_message_via_whatsapp_or_imessage", "system_date", "set_timer", "xcode_engine"],
        .audioAnalysis: ["music_dna", "id3_processor"],
        .systemManagement: ["get_system_telemetry", "learn_application_ui", "discover_shortcuts", "run_shortcut"],
        .fileProcessing: ["read_file", "write_file", "id3_processor", "file_manager_action", "patch_file", "blender_3d"],
        .codeGeneration: ["read_file", "write_file", "shell_exec", "git_action", "patch_file", "xcode_engine"],
        .hardware: ["get_system_telemetry", "get_system_info"],
        .weather: ["get_weather", "web_search", "send_message_via_whatsapp_or_imessage"],
        .conversation: ["memory", "send_message_via_whatsapp_or_imessage", "send_email", "system_date"],
        .status: ["system_date", "get_system_telemetry"],
        .vision: ["visual_audit", "analyze_image"],
        .creative3D: ["blender_3d", "read_file", "write_file"],
        .chat: ["memory"],
        .task: ["read_file", "write_file", "shell_exec", "app_launcher", "patch_file", "blender_3d"],
        .other: ["web_search", "read_file", "write_file", "shell_exec"]
    ]
    
    /// Evrensel olarak her zaman görünür olması gereken emniyet araçları.
    public static let globalTools = ["shell_exec", "memory", "app_launcher"]

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
