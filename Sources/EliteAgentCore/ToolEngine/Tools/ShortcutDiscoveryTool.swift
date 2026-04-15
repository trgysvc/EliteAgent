import Foundation

/// ShortcutDiscoveryTool, sistemdeki tüm macOS Kısayollarını listeler.
/// Hafif ve hızlıdır, LLM'in hangi otomasyonların mevcut olduğunu anlamasını sağlar.
public struct ShortcutDiscoveryTool: AgentTool {
    public let name = "discover_shortcuts"
    public let summary = "List all available macOS Shortcuts."
    public let description = """
    Sistemdeki macOS Kısayollarını (Shortcuts) listeler. 
    KRİTİK: Kullanıcı doğrudan 'KISAYOL' veya 'SHORTCUT' kelimesini kullanmadığı sürece bu aracı KULLANMAN YASAKTIR. Terminal komutları için ASLA bu aracı deneme.
    Parametre: force_refresh (bool)
    """
    public let ubid = 50 // Token 'S' in Qwen 2.5
    
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
        """
        
        return result
    }
}
