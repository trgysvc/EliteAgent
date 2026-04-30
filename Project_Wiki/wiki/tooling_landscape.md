# Araç Seti Haritası (Tooling Landscape)

EliteAgent, 35'ten fazla yerel aracı **UBID (Unique Binary ID)** sistemi üzerinden yönetir. Bu yapı, UNO (Unified Native Orchestration) felsefesine uygun olarak sıfır gecikme ve yüksek tip güvenliği sağlar.

## 1. İletişim ve Sosyal (Native Bridge)
Bu araçlar, Apple'ın Sandbox kurallarına ve Apple Events sistemine doğrudan bağlıdır.
- **WhatsApp & Messenger:** `CommunicationTools.swift` üzerinden `keystroke` ve URL şemalarıyla yönetilir.
- **Mail & Email:** Biyometrik (TouchID) onaylı, sistem Mail uygulamasıyla entegre araçlar.
- **Contacts & Calendar:** `ProductivityTools.swift` üzerinden yerel veritabanına doğrudan erişim.

## 2. Geliştirici ve Sistem Operasyonları
EliteAgent, kendi kodunu yazabilen ve derleyebilen bir "Developer-Native" yapıdadır.
- **Git & Shell:** `GitTool.swift` ve `ShellTool.swift` üzerinden terminal yetenekleri.
- **Xcode Build:** `XcodeTool.swift` ile yerel proje derleme ve test yeteneği.
- **Patch & Write:** `PatchTool.swift` ile kod tabanına atomik değişiklikler uygulama.

## 3. Web ve Araştırma Süiti
Dış dünya ile güvenli veri alışverişi sağlayan katman.
- **Safari Automation:** Safari'yi `AppleEvents` ile kontrol eden native bridge.
- **Native Browser:** Harici tarayıcı ihtiyacını ortadan kaldıran sistem içi tarayıcı.
- **Web Search/Fetch:** Araştırma görevleri için optimize edilmiş asenkron araçlar.

## 4. Uzmanlaşmış Medya ve Sistem Kontrolü
Donanım seviyesinde kontrol sağlayan düşük seviyeli araçlar.
- **MusicDNA:** Ses analizi ve müzik işleme yeteneği.
- **Ecosystem Tools:** Parlaklık, ses, uyku modu gibi donanım parametrelerini yöneten `set_volume`, `set_brightness` araçları.

## 5. İleri AI ve Hafıza
Ajanın kendi iç süreçlerini yönettiği meta-araçlar.
- **Context Memory:** `MemoryTool.swift` ile uzun dönemli bağlam yönetimi.
- **Subagent (Task Delegation):** Karmaşık görevleri alt ajanlara bölüştüren orkestrasyon aracı.

---
**Felsefi Not:** Tüm araçlar, JSON gibi metin tabanlı protokoller yerine **UBID** ve **Typed Swift Parameters** kullanarak UNO omurgasında asenkron (async/await) olarak çalışır.
