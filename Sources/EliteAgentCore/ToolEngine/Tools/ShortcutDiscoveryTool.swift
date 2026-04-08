import Foundation

/// ShortcutDiscoveryTool, sistemdeki tüm macOS Kısayollarını listeler.
/// Hafif ve hızlıdır, LLM'in hangi otomasyonların mevcut olduğunu anlamasını sağlar.
public struct ShortcutDiscoveryTool: AgentTool {
    public let name = "discover_shortcuts"
    public let description = """
    Sistemdeki macOS Kısayollarını (Shortcuts) listeler. 
    SADECE kullanıcı doğrudan bir kısayol aranması talep ettiğinde KULLANILMALIDIR. Aksi halde başka işlemler için ASLA KULLANMA.
    Parametre: force_refresh (bool)
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
        """
        
        return result
    }
}
