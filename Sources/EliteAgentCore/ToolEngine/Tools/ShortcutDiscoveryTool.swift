import Foundation

/// ShortcutDiscoveryTool, sistemdeki tüm macOS Kısayollarını listeler.
/// Hafif ve hızlıdır, LLM'in hangi otomasyonların mevcut olduğunu anlamasını sağlar.
public struct ShortcutDiscoveryTool: AgentTool {
    public let name = "discover_shortcuts"
    public let description = """
    macOS sistemindeki tüm yüklü Kısayolları (Shortcuts) listeler. 
    Eğer kullanıcı belirli bir uygulama için (örneğin Slack, Notion) bir işlem yapmak istiyorsa 
    ve sistemde hazır bir araç yoksa bu araçla ilgili kısayolun olup olmadığını kontrol edebilirsin.
    Parametre: force_refresh (bool - isteğe bağlı, listeyi güncel sistemden çeker).
    """
    
    public init() {}
    
    public func execute(params: [String: AnyCodable], session: Session) async throws -> String {
        let forceRefresh = params["force_refresh"]?.value as? Bool ?? false
        
        let shortcuts = await ShortcutCache.shared.getShortcuts(forceRefresh: forceRefresh)
        
        if shortcuts.isEmpty {
            return "Sistemde yüklü herhangi bir macOS Kısayolu bulunamadı."
        }
        
        let result = """
        [Shortcut Discovery] Sistemde \(shortcuts.count) adet kısayol bulundu:
        - \(shortcuts.joined(separator: "\n- "))
        
        İpucu: Bir kısayolu çalıştırmak için 'run_shortcut' aracını kullanabilirsin.
        """
        
        return result
    }
}
