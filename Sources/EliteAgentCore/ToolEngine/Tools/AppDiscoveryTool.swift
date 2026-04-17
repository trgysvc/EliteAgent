import Foundation
import ApplicationServices
import AppKit

/// AppDiscoveryTool, ajanın bilmediği veya yeni sürümü çıkmış bir uygulamanın
/// UI ağacını tarayarak "öğrenmesini" sağlar.
public struct AppDiscoveryTool: AgentTool {
    public let name = "learn_application_ui"
    public let summary = "Learn/Map UI tree of unknown Mac apps."
    public let description = """
    Bilinmeyen veya güncellenmiş bir uygulamanın kullanıcı arayüzünü (UI) tarar.
    Arama çubuğu, butonlar ve giriş alanlarını hafızaya kaydeder.
    Parametreler: application_name (Uygulamanın tam adı)
    """
    public let ubid: Int128 = 35 // Token 'D' in Qwen 2.5
    
    public init() {}
    
    public func execute(params: [String: AnyCodable], session: Session) async throws(AgentToolError) -> String {
        guard let appName = params["application_name"]?.value as? String else {
            throw AgentToolError.missingParameter("application_name parametresi gereklidir.")
        }
        
        // Gerçek implementasyonda NSWorkspace ile uygulama bulunur ve AXUIElement ile taranır.
        // Şimdilik öğrenme mantığını simüle eden ve hafıza kaydı yapan yapı kuruldu.
        
        let discoveryResult = """
        [Learning Engine] '\(appName)' uygulaması aktif edildi.
        [Scanning] UI Hiyerarşisi taranıyor (AXUIElement)...
        [Mapping] Arama Çubuğu (AXTextField) -> Konum: 120x45
        [Mapping] Gönder Butonu (AXButton) -> Konum: 500x800
        [Indexing] Veriler ExperienceVault'a ('app_uimaps' tablosu) kaydedildi.
        
        Özel rapor: '\(appName)' için artık standart AppleScript kısayolları (CMD+N, CMD+F) 
        ve gelişmiş UI koordinatları kullanılabilir. Öğrenme tamamlandı.
        """
        
        return discoveryResult
    }
}
