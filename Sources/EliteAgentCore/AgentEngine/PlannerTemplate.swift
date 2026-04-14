import Foundation

public struct PlannerTemplate: Sendable {
    public static func generateAgenticPrompt(session: Session, ragContext: String = "", toolSubset: [any AgentTool]? = nil) async -> String {
        let depth = session.recursionDepth
        let maxDepth = session.maxRecursionDepth
        let workspace = session.workspaceURL.path
        
        let toolsToDisplay: [String]
        if let subset = toolSubset {
            // v19.7.7: Unmask full descriptions and parameter requirements for the Planner
            toolsToDisplay = subset.map { "- [\($0.ubid)] \($0.name): \($0.description)" }
        } else {
            // Default to Master Toolset if no subset provided (Full Escalation Mode)
            toolsToDisplay = [
                "- [32] `shell_exec`: Terminal komutu çalıştırır (zsh). Parametre: command (string).",
                "- [33] `read_file`: Dosya içeriğini yerel Swift API'leri ile okur. Parametre: path (string).",
                "- [34] `write_file`: Dosya içeriğini yerel Swift API'leri ile yazar (MANDATORY). Parametreler: path, content.",
                "- [37] `messenger`: iMessage/WhatsApp mesajı gönderir (Native).",
                "- [40] `safari_automation`: Safari otomasyonu ve Google arama (NATIVE).",
                "- [45] `web_search`: Google araması yapar (WebFetch). Parametre: query (string)."
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
        5. **DİL KİLİDİ (MUTLAK)**: Tüm yanıtların YALNIZCA TÜRKÇE olmalıdır. Çince veya başka bir dil KESİNLİKLE YASAKTIR.
        6. **Bitiş Sinyali (DONE)**: Görev tamamen bittiyse ve yapacak başka işin kalmadıysa SADECE `<final>DONE</final>` yaz. Motor bu sinyali alana kadar çalışmaya devam eder.
        
        ### ⚠️ KRİTİK DONANIM VE OPERASYON KURALLARI (MUTLAK):
        1. **Atomik İcra**: `shell_exec` içinde asla 2'den fazla komutu `&&` ile birleştirme. Her kritik adımı ayrı bir turda çalıştır ve sonucunu gör.
        2. **Doğrudan Araç Kullanımı**: Dosya oluşturmak için shell `echo` yerine DAİMA `write_file` (UBID 34) aracını kullan.
        3. **Araç Seçimi (RESEARCH)**: İnternette araştırma yapmak veya bir sayfa içeriğini çekmek için KESİNLİKLE `shell_exec` veya `osascript` (AppleScript) kullanma. Bu BİR HATTIR. Daima `web_search` (UBID 45) veya `web_fetch` (UBID 46) kullan.
        4. **Donanım Sorguları**: CPU yükü, bellek, RAM gibi HERHANGİ bir donanım sorgusu için ASLA shell komutları (`top`, `ps` vb.) KULLANMA. ZORUNLU OLARAK `get_system_telemetry` (UBID 36) kullan.
        5. **Sıralı İcra (Sequential Atomicity)**: AYNI YANIT İÇİNDE ASLA BİRDEN FAZLA YAZMA/OKUMA ARACI KULLANMA. Örneğin internetten veri çekip dosyaya yazacaksan; ÖNCE arama aracını çalıştır, SONRA gelen "Observation" çıktısını bekle. Gerçek veriyi görene kadar yazma aracını (`write_file`) çalıştırmak KESİNLİKLE YASAKTIR.
        
        ### 🌦 HAVA DURUMU KURALI (WEATHER DNA):
        - Hava durumu sorgularında (şimdi, yarın veya belirli bir tarih) DAİMA `get_weather` (UBID 52) aracını kullan.
        - `day` parametresine kullanıcının belirttiği tarihi (örn: "13 nisan", "pazartesi") olduğu gibi aktar.
        - Çıktıyı kullanıcıya sunarken aracın döndürdüğü zengin dashboard formatını (widget görünümü) KESİNLİKLE BOZMA, ÖZETLEME VE TÜRKÇELEŞTİRME. Dashboard verisini aynen (raw) yansıt.
        
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
