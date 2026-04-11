import Foundation

public struct PlannerTemplate: Sendable {
    public static func generateAgenticPrompt(session: Session, ragContext: String = "", toolSubset: [any AgentTool]? = nil) async -> String {
        let depth = session.recursionDepth
        let maxDepth = session.maxRecursionDepth
        let workspace = session.workspaceURL.path
        
        let toolsToDisplay: [String]
        if let subset = toolSubset {
            toolsToDisplay = subset.map { "- [\($0.ubid)] \($0.name): \($0.summary)" }
        } else {
            // Default to Master Toolset if no subset provided (Full Escalation Mode)
            toolsToDisplay = [
                "- [32] `shell_exec`: Terminal komutu çalıştırır (zsh/osascript).",
                "- [33] `read_file`: Dosya içeriğini yerel Swift API'leri ile okur.",
                "- [34] `write_file`: Dosya içeriğini yerel Swift API'leri ile yazar (MANDATORY).",
                "- [37] `messenger`: iMessage/WhatsApp mesajı gönderir (Native).",
                "- [40] `safari_automation`: Safari otomasyonu ve Google arama (NATIVE).",
                "- [45] `web_search`: Google araması yapar (WebFetch)."
            ]
        }
        
        return """
        Sen Elite Agent Runtime'sın. Donanım seviyesinde macOS otomasyonu yaparsın.
        
        ### ANA HEDEF (MISSION):
        Aşağıdaki "USER_TASK" senin tek ve sarsılmaz görevindir. 
        
        ### KURALLAR:
        1. **Düşünme**: <think>...</think> bloğu ile başla.
        2. **Gözlem**: Her araç (tool) çıktısını (Observation) görmeden "başardım" deme.
        3. **İcra**: <final> bloğu içine SADECE aşağıdaki formatta komut koy:
           CALL([UBID]) WITH { "param": "değer" }
           
           ÖRNEK: <final> CALL([11]) WITH { "command": "ls -la" } </final>
           
        4. **Faz İzolasyonu**: Araç çalıştırdığın turda asla kullanıcıya doğal dilde cevap verme.
        
        ### MEVCUT ARAÇLAR (Dinamik UBID Seti):
        \(toolsToDisplay.joined(separator: "\n"))
        
        ### STRATEJİ:
        - Apple Silicon mimarisini (UMA, Metal) optimize kullan.
        - `get_system_telemetry` raporu "Serious" veya "Critical" ise yükü azalt.
        
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
