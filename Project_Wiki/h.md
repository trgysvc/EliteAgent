# Hot Memory (Güncel Durum) - 2026-04-30

## ACTIVE MISSION: Native Sovereign Transition
Sistemi reaktif yapıdan proaktif "Yerel Egemen" yapıya taşıma (Sprint: v7.0 Stability).

## 🎯 TOP 3 PRIORITIES
1. **Proactive UMA Watchdog:** Global session pause ve emergency consolidation entegrasyonu tamamlandı. ✅
2. **UNO Pointer Migration:** SharedMemoryPool ve zero-copy transport (64KB eşiği) tamamlandı. ✅
3. **Context & Failure Management:** Preemptive overflow check ve Failover Policy (Aşama 3) tamamlandı. ✅
4. **MLX-Native Cleanup:** `BPETokenizer` entegrasyonu tamamlandı, %100 native MLX tokenization'a geçildi. ✅

## Proje Durumu (Specific Context)
- **Versiyon:** 7.8.5 (v7.0 Stability Sprint - Phase 1-4 COMPLETED)
- **Aktif Görev:** Aşama 1-4 tamamlandı. Aşama 5 (Blender Bridge Stabilization) hazırlanıyor.
- **Model:** Titan v2 (Qwen 3.5 MLX) - Yerel Çıkarım.
- **Araç Seti:** 35 aktif araç, tamamı UBID (Unique Binary ID) ile UNO omurgasına kayıtlı.
- **Güvenlik Katmanı:** Kritik araçlarda (TouchID) biyometrik onay ve Apple Events sandbox kısıtlamaları devrede.

## Teknik Detaylar (Hot context)
- **VRAM Yönetimi:** UMA Teşhisi ile OOM hataları otomatik engelleniyor.
- **İletişim Gecikmesi:** WhatsApp operasyonlarında 1.0s stabilizasyon gecikmesi uygulanıyor.
- **UI:** `isInputLocked` hatası giderildi, araç yürütme sırasında kullanıcı arayüzü stabil.
- **Analiz:** `wiki/gap_analysis.md` (Vizyon) ve `wiki/tooling_landscape.md` (Araçlar) üzerinden sistemin native derinliği takip ediliyor.

## Mimari Vizyon
EliteAgent, her türlü middleware'den (LangChain vb.) arındırılmış, doğrudan Apple API'leri ve MLX ile konuşan bir "Native Sovereign" (Yerel Egemen) sistemdir. Gelecek adımlar, UNO protokolünü "Pointer-Native" seviyesine çekerek sıfır kopyalama maliyetli veri transferini sağlamaktır.

## Öğrenilmiş Dersler (Lessons Learned)
- **VRAM Yönetimi:** 16GB sistemlerde rastgele VRAM kilitlenmelerini önlemek için Apple'ın `recommendedMaxWorkingSetSize` API'si kullanılmalı; hardcoded yüzdelerden (%55 vb.) kaçınılmalı.
- **Döngü Engelleme:** Ajanın "Observation" mesajlarını görmezden gelip aynı hatalı komutu tekrarlamasını engellemek için SHA-256 tabanlı `LoopDetector` her zaman aktif tutulmalı.
- **Bağlam Sıkıştırma:** Otomatik sıkıştırma (compaction) sırasında dosya yolları ve hata kodları silinirse ajan "yolunu kaybediyor". Bu veriler `Must-Preserve` listesinde kalmalı.
- **Swift Versiyonu:** Dağıtık makinelerde çalışırken `Package.swift` tools version mismatch hatalarını önlemek için projenin en yaygın kararlı sürümü (örn. 6.0.0) hedeflenmeli.
- **Path Migration:** Sistem güncellemelerinde `Models` klasörü taşınmazsa, kullanıcı modellerin silindiğini sanabiliyor; her zaman tam path migration yapılmalı.
- **Layout Recursion:** SwiftUI `NSHostingController` içinde sonsuz döngüleri (0x5) önlemek için `sizingOptions = []` kuralı uygulanmalı.

## Bekleyen İşlemler
- `Project_Wiki` dizinindeki orphan node'ların (raw/ dosyaları) entegrasyonu tamamlandı. ✅
- Tüm teknik dökümanlar (`wiki/`) arasında bağlamsal linkleme (Contextual Linking) yapıldı. ✅
- [[gap_analysis]] dökümanı v7.8.5 durumuna göre güncellendi.

