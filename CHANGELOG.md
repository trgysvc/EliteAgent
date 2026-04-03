# Changelog

Tüm önemli değişiklikler bu dosyada listelenmektedir.

## [7.8.5] - 2026-04-04

### Added
- **Titan v2 (Qwen 3.5 MLX) Entegrasyonu**: Yerel çıkarım motoru en yeni mimari ile güncellendi.
- **GGUF Bütünlük Kalkanı**: Bozuk veya uyumsuz model dosyaları için otomatik dosya başlığı doğrulaması eklendi.
- **Birleşik Bellek (Unified Memory) Teşhisi**: macOS sistemlerinde kritik bellek basıncı durumunda OOM hatalarını önlemek için otomatik yükleme blokajı eklendi.
- **Privacy Manifest (2024)**: Apple'ın yeni gizlilik gereksinimlerine tam uyum için `PrivacyInfo.xcprivacy` eklendi.
- **Inference Analytics Dashboard**: Settings panelinden anlık Latency (milisaniye) ve TPS (Token Per Second) takibi sağlandı.

### Fixed
- **WhatsApp Mesajlaşma Kararlılığı**: URL açılışı ve otomatik tuş vuruşu ("keystroke return") arasındaki zamanlama hatası giderildi (0.5s → 1.0s gecikme).
- **Tool Parametre Hataları**: LLM'in eksik parametre göndermesi durumunda oluşan "Error 0" hatası, insan tarafından okunabilir "Eksik Parametre" mesajlarıyla değiştirildi.
- **Zorunlu Yerel (Strict Local) Modu**: Cloud'a sessiz geçiş hataları giderildi, kullanıcı onayı mekanizması güçlendirildi.
- **UI State Kilidi**: Bir araç hata verdiğinde girdi alanının kilitli kalması sorunu (`isInputLocked`) çözüldü.

### Security
- **Biyometrik Onay Koruması**: Kritik sistem araçları (E-posta, Mesaj) için TouchID onayı zorunluluğu pekiştirildi.
- **Sandbox Sıkılaştırması**: Apple Events yetkileri sadece gerekli bundle'lar ile sınırlandırıldı.
