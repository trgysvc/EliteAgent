# Hot Memory (Güncel Durum) - 2026-05-01

## ACTIVE MISSION: Native Sovereign Transition
Sistemi reaktif yapıdan proaktif "Yerel Egemen" yapıya taşıma (Sprint: v7.0 Stability).

## 🎯 TOP 3 PRIORITIES
1. **Phase 1: Graph Mühürleme:** `mx.compile` + Fixed-Shape Padding entegrasyonu. (KRİTİK) 🚀
2. **Phase 2: KV-Cache Frozen State:** Shared Prefix (`KVCache.offset`) ile TTFT optimizasyonu. 🏗️
3. **Phase 3: Hardware IPC:** IOSurface tabanlı Zero-Copy XPC Transport araştırması. 🧪

## Proje Durumu (Specific Context)
- **Versiyon:** 7.0.0 "Native Sovereign" (OFFICIAL RELEASE)
- **Aktif Görev:** v7.0 kararlılık sprinti tamamlandı. "Hot Memory" (Sıcak Hafıza) süreklilik katmanı için altyapı hazır.
- **Model:** Titan v2 (Qwen 3.5 MLX) - Yerel Çıkarım (Zero-Copy Enabled).
- **Araç Seti:** 38 aktif araç, tamamı UBID (Unique Binary ID) ile UNO omurgasına kayıtlı.
- **Güvenlik Katmanı:** Kritik araçlarda (TouchID) biyometrik onay ve Apple Events sandbox kısıtlamaları devrede.

## Teknik Detaylar (Hot context)
- **Zero-Copy Highway:** SharedMemoryPool üzerinden veri transferi 0.1ms altına çekildi.
- **VRAM Yönetimi:** UMA Watchdog ile OOM hataları %100 engelleniyor.
- **UI:** Layout recursion hataları (0x5) giderildi, macOS 15.0+ Sequoia tam uyumluluğu sağlandı.
- **Analiz:** `wiki/gap_analysis.md` (Vizyon) ve `wiki/tooling_landscape.md` (Araçlar) üzerinden sistemin native derinliği takip ediliyor.

## Mimari Vizyon
EliteAgent, her türlü middleware'den (LangChain vb.) arındırılmış, doğrudan Apple API'leri ve MLX ile konuşan bir "Native Sovereign" (Yerel Egemen) sistemdir. v7.0 ile UNO protokolü "Pointer-Native" seviyesine çekilerek sıfır kopyalama maliyetli veri transferi sağlanmıştır. Gelecek adım, bu işaretçilerin (pointers) oturumlar arası kalıcılığını sağlayacak "Hot Memory" implementasyonudur.

## Öğrenilmiş Dersler (Lessons Learned)
- **VRAM Yönetimi:** 16GB sistemlerde rastgele VRAM kilitlenmelerini önlemek için Apple'ın `recommendedMaxWorkingSetSize` API'si kullanılmalı; hardcoded yüzdelerden (%55 vb.) kaçınılmalı.
- **Döngü Engelleme:** Ajanın "Observation" mesajlarını görmezden gelip aynı hatalı komutu tekrarlamasını engellemek için SHA-256 tabanlı `LoopDetector` her zaman aktif tutulmalı.
- **Bağlam Sıkıştırma:** Otomatik sıkıştırma (compaction) sırasında dosya yolları ve hata kodları silinirse ajan "yolunu kaybediyor". Bu veriler `Must-Preserve` listesinde kalmalı.
- **Swift Versiyonu:** Dağıtık makinelerde çalışırken `Package.swift` tools version mismatch hatalarını önlemek için projenin en yaygın kararlı sürümü (örn. 6.0.0) hedeflenmeli.
- **Path Migration:** Sistem güncellemelerinde `Models` klasörü taşınmazsa, kullanıcı modellerin silindiğini sanabiliyor; her zaman tam path migration yapılmalı.
- **Layout Recursion:** SwiftUI `NSHostingController` içinde sonsuz döngüleri (0x5) önlemek için `sizingOptions = []` kuralı uygulanmalı.

## Bekleyen İşlemler
- `Project_Wiki` teknik dökümantasyon mührü vuruldu. ✅
- Performans ve Optimizasyon Araştırması (v7.1 Revize) tamamlandı. ✅
- `wiki/performance_roadmap.md` (v7.1) mühürlendi. ✅
- **Sıradaki Odak Noktası:** Phase 1: `mx.compile` + Fixed-Shape Padding (Graph Mühürleme).

## Önemli Notlar
- Donanım kısıtları artık sistemin "tasarım girdisi" olarak kabul ediliyor.
- Her yeni araç veya özellik, MLX grafik yapısına ve Metal bant genişliğine olan etkisine göre değerlendirilecek.

