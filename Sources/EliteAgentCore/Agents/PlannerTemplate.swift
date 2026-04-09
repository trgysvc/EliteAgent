import Foundation

public struct PlannerTemplate: Sendable {
    public static func generateAgenticPrompt(session: Session, ragContext: String = "", toolSubset: [any AgentTool]? = nil) async -> String {
        let depth = session.recursionDepth
        let maxDepth = session.maxRecursionDepth
        let workspace = session.workspaceURL.path
        
        let toolsToDisplay: [String]
        if let subset = toolSubset {
            toolsToDisplay = subset.map { "- \($0.name): \($0.description)" }
        } else {
            // Default to Master Toolset if no subset provided (Full Escalation Mode)
            toolsToDisplay = [
                "- `shell_exec`: (params: [\"command\": \"...\"]) - AppleScript veya Terminal.",
                "- `read_file`, `write_file`, `patch_file` - Dosya işlemleri.",
                "- `send_message_via_whatsapp_or_imessage`: (params: [\"platform\", \"recipient\", \"message\"])",
                "- `apple_calendar`, `apple_mail`, `media_control` - Native App kontrolü.",
                "- `browser_native`, `web_search`, `web_fetch` - İnternet/Tarayıcı.",
                "- `get_system_telemetry` - Donanım (Isı, RAM, CPU) takibi.",
                "- `shortcut_execution`, `run_shortcut`, `discover_shortcuts`."
            ]
        }
        
        return """
        Sen Elite Agent Runtime'sın. Donanım seviyesinde macOS otomasyonu yaparsın.
        
        ### KURALLAR:
        1. **Düşünme**: <think>...</think> bloğu ile başla.
        2. **Gözlem**: Her araç (tool) çıktısını (Observation) görmeden "başardım" deme.
        3. **Döngü**: Bir araç hata verirse aynı parametrelerle tekrar çağırma.
        4. **İcra**: <final> bloğu içine SADECE JSON komutu koy. Görev bittiğinde insan diliyle özet geç.
        5. **Dürüstlük**: Kimliğini saklama, neleri yapamayacağını net söyle.
        6. **Veri Bütünlüğü**: Parametrelerde ASLA `[ilgili bilgi]`, `[buraya veri]` gibi taslak (placeholder) ifadeler kullanma. Eğer veriye sahip değilsen, mesaj göndermeden ÖNCE o veriyi çekecek araçları (google_search, weather vb.) çalıştır. Gerçek veri olmadan mesaj gönderme.
        7. **Faz İzolasyonu**: Araç çalıştırdığın turda (tool_call) asla kullanıcıya doğal dilde cevap verme. Cevabı sadece araç Gözlem (Observation) verdikten sonraki turda ver.
        
        ### MEVCUT ARAÇLAR (Dinamik Toolset):
        \(toolsToDisplay.joined(separator: "\n"))
        
        ### STRATEJİ:
        
        ### STRATEJİ:
        - Apple Silicon mimarisini (UMA, Metal) optimize kullan.
        - `get_system_telemetry` raporu "Serious" veya "Critical" ise yükü azalt.
        - Her uygulamayı en spesifik aracı veya `osascript` ile yönet.
        
        Depth: \(depth)/\(maxDepth) | Workspace: \(workspace)
        \(ragContext.isEmpty ? "" : "### BELLEK:\n\(ragContext)")
        
        BAŞLA!
        """
    }

    public static func generatePrompt(task: String, category: TaskCategory, complexity: Int) -> String {
        // Keep legacy prompt for backward compatibility if needed, but we'll transition to V2
        return """
        Sen Elite Agent Planner'sın (macOS Native).
        Görev: \(task)
        Kategori: \(category.rawValue)
        Zorluk Puanı: \(complexity)/5
        ... (legacy content) ...
        """
    }
}
