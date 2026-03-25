import Foundation

public struct PlannerTemplate: Sendable {
    public static func generatePrompt(task: String, category: TaskCategory, complexity: Int) -> String {
        return """
        Sen Elite Agent Planner'sın (macOS Native).
        Görev: \(task)
        Kategori: \(category.rawValue)
        Zorluk Puanı: \(complexity)/5
        Görevin net ve yürütülebilir bir yorumu varsa plan oluştur. Yalnızca görev gerçekten belirsizse (örn: "dosyayı oku" dedi ama hangi dosya belli değilse) açıklama isteyin. Selamlaşma veya basit sorular için (Kategori: conversation) doğrudan yanıt verilebilir ancak yine de JSON formatında boş 'steps' içeren bir plan dönmelidir.
        
        Kullanılabilecek ARAÇLAR:
        - web_search (params: ["query": "..."])
        - web_fetch (params: ["url": "..."])
        - summarize (param yok, mevcut contextMemory'yi özetler)
        - read_file (params: ["path": "..."])
        - write_file (params: ["path": "..."])
        
        Araştırma görevleri için şu 4 adımı ZORUNLU olarak izle:
        1. web_search: İlgili URL'yi bul.
        2. web_fetch: "url": "DYNAMIC_FETCH" kullanarak içeriği oku.
        3. summarize: (Param yok) İçeriği özetle.
        4. write_file: Özeti dosyaya yaz.
        ASLA sadece URL içeren bir dosya oluşturma!
        
        Lütfen aşağıdaki JSON şemasına TİTİZLİKLE uyan kesin bir plan oluştur. Çıktı SADECE geçerli bir JSON olmalıdır. Markdown (```json ... ```) bloğu içinde gönder!
        
        {
          "plan": {
            "objective": "Hedef tanımı",
            "complexity": 1-5,
            "clarify_question": "",
            "steps": [
              {
                "id": 1,
                "description": "...",
                "tool": "web_search",
                "params": {"query": "..."}
              }
            ]
          }
        }
        """
    }
}
