# EliteAgent — Technical Audit Tasks

Generated: 2026-05-02

Bu dosya, repository genelinde yaptığım teknik tarama sonucunda oluşturulan öncelikli yapılacaklar listesidir. Her görev kısa açıklama, etkilediği dosyalar/konumlar, öncelik ve önerilen düzeltme stratejisini içerir. Onayınızla bu görevleri tek tek uygulayıp her değişiklik sonrası derleme ve testleri çalıştıracağım.

---

## Hızlı Özet
- Yapılan işlem: repo genelinde derleme, regex taramaları, Apple/MLX/Sparkle dokümantasyon taraması.
- Toplam taranan Swift kaynak dosyası: 206
- Mevcut build sonucu: `swift build` — Build complete! (uyarılar mevcut)
- En kritik bulgular: Sparkle güncelleme anahtarı placeholder (güvenlik), `Package.swift` içinde duplicate `MLX` product uyarısı, Unsafe/Unmanaged kullanan IPC/shared-memory kodu, `@preconcurrency` kullanımları, CoreML dinamik yükleme noktaları.

---

## Checklist (yapılacaklar — onay verildikçe işleme alınacak)
1. [ ] Sparkle: `SUPublicEDKey` gerçek EdDSA public key ile değiştir, appcast imza doğrulamasını test et. (Acil — Güvenlik)
2. [x] `Package.swift` temizliği: duplicate `MLX` tanımlarını kaldır, hedef bağımlılıklarını sadeleştir. (Tamamlandı)
3. [x] Unsafe/Unmanaged review: `UNORingBuffer`, `MachPortCoordinator` vb. yeni altyapıda ownership/guard uygulandı. (Tamamlandı)
4. [ ] `@preconcurrency` stratejisi: kullanım yerlerini belgeleyip, kritik Obj‑C tiplerini `@MainActor` veya actor içlerine taşıma planı hazırla. (Düşük–Orta)
5. [ ] CoreML model yükleme: `ANEInferenceActor.swift` içinde model yükleme hata/log iyileştirmeleri ve model doğrulama ekle. (Orta)
6. [x] Swift Concurrency / Sendable: `UNOTransport`, `UNODistributedActorSystem` ve `InferenceActor` Swift 6.3 standartlarına göre modernize edildi. (Tamamlandı)
7. [ ] Static analysis & lint: Xcode Analyze + SwiftLint çalıştır, yüksek öncelikli uyarıları düzelt. (Orta)
8. [/] Unit tests: `swift test` derleme hataları giderildi, testler çalıştırılıyor. (Devam Ediyor)
9. [ ] Sparkle workflow testleri: appcast ve imzalama araç zincirini CI/yerelde doğrula. (Yüksek)
10. [x] Dokümantasyon: `DEVLOG.md` ve `walkthrough.md` güncellendi. (Tamamlandı)

---

## Detaylı Görevler ve Önerilen Düzeltme Stratejileri

### 1) Sparkle: Update signing key ve appcast doğrulama
- Etki alanı / Dosyalar: `Resources/App/Info.plist` (SUPublicEDKey, SUFeedURL)
- Problem: `SUPublicEDKey` şu an placeholder değerde. Bu, Sparkle ile imzalanmış güncellemelerin doğrulanmasını engellerse güvenlik riski yaratır.
- Öneri: Gerçek EdDSA public key'i yerleştirin ve `generate_appcast` / `sign_update` araç zincirini kullanarak hem appcast'i hem de bileşenleri imzaladığınızdan emin olun. Test için lokal appcast ve imza doğrulama çalıştırın.
- Onarım adımları (kısa):
  - Gerçek `SUPublicEDKey` ekle veya deployment pipeline'da doğru anahtar yönetimini uygulayın.
  - Console.app loglarını kontrol ederek Sparkle imza doğrulamasını test edin.

### 2) `Package.swift` tidy — duplicate MLX product
- Etki alanı / Dosyalar: `Package.swift`, `Package.resolved`
- Problem: `swift build` başlangıcında "ignoring duplicate product 'MLX'" uyarısı var. `Package.swift` içinde bazı hedeflerde MLX tekrarları bulunuyor.
- Öneri: Duplicate `.product(name: "MLX", package: "mlx-swift")` girişlerini kaldır, MLX linklemesini tekilleştir. Mümkünse MLX'i sadece `EliteAgentCore`'e ekleyip diğer hedefleri core'a bağımlı yap.
- Onarım adımları:
  - `Package.swift`'i değiştirip duplicate satırları kaldır.
  - `swift build` çalıştır ve uyarının kaybolduğunu doğrula.

### 3) Unsafe/Unmanaged kod incelemesi
- Etki alanı / Dosyalar: `Sources/EliteAgentCore/AgentEngine/ProjectObserver.swift`, `Sources/EliteAgentCore/ToolEngine/PluginManager.swift`, `Sources/EliteAgentCore/UNO/UNOSharedBuffer.swift`, `Sources/EliteAgentCore/UNO/SharedMemoryPool.swift` ve benzerleri.
- Problem: `Unmanaged.fromOpaque(...).takeUnretainedValue()` ve `UnsafeMutableRawPointer` kullanımları ownership sorunlarına yol açabilir.
- Öneri: Her bir kullanım için ownership yorumları ekle, gerekiyorsa `takeRetainedValue()` / `takeUnretainedValue()` doğru kullanıldığından emin ol; sarmalayıcı helper fonksiyonlar oluştur. Ek testler ekleyin.

### 4) `@preconcurrency` kullanım planı
- Etki alanı / Dosyalar (örnekler): `ExtraUtilityTools.swift` (`CoreLocation`), `InferenceActor.swift` (`MLX`), `Types.swift` (`Metal`) vb.
- Problem: Objective‑C bridged modüller veya concurrency-ataması olmayan paketler için `@preconcurrency` kullanılmış. Bu kısa vadede işe yarar ama teknik borç oluşturur.
- Öneri: `@preconcurrency`'yi belgeleyin; kritik Obj‑C tiplerini `@MainActor` veya actor içine taşıyın. Uzun vadede tipleri `Sendable` hale getirin veya izolasyon uygulayın.

### 5) CoreML dynamic model loading hardening
- Etki alanı / Dosyalar: `Sources/EliteAgentCore/LLM/ANEInferenceActor.swift`
- Problem: Dinamik model yüklemelerinde (MLModel(contentsOf:)) runtime hataları olabilir.
- Öneri: Daha ayrıntılı hata kaydı ve model doğrulama, model paketleme yönergeleri ve (varsa) model encryption/adoption uygulayın.

### 6) Swift Concurrency / Sendable review
- Etki alanı / Dosyalar: repo genelinde `@unchecked Sendable` ve `Sendable` işaretlemeleri (ör. `UNOXPCService`), actor ve shared state kullanımları.
- Problem: `@unchecked Sendable` kullanımı potansiyel veri yarışlarına neden olabilir.
- Öneri: `@unchecked Sendable` kullanımlarını inceleyin, immutable hale getirin veya actor kapsüllemelerine taşıyın.

### 7) Static analysis & tests
- İlerlemede yapılacaklar:
  - `xcodebuild analyze` veya Xcode Analyze çalıştırın ve önemli uyarıları çözün.
  - `swift test` çalıştırın, test başarısızlıklarını raporlayın.

---

## Komutlar (kopyala/çalıştır)
Derleme ve test komutları:
```bash
cd /Users/trgysvc/Developer/EliteAgent
swift build
swift test
```

Xcode analiz (yerel Xcode gerektirir):
```bash
xcodebuild -workspace EliteAgent.xcworkspace -scheme EliteAgent -configuration Debug analyze
```

SwiftLint (lokalde kuruluysa):
```bash
swiftlint lint --config .swiftlint.yml
```

---

## Onay ve Sonraki Adımlar
Lütfen hangi görevlerin öncelikli olmasını istediğinizi onaylayın (örneğin: 1 ve 2 hemen; 3'ü takip eden sprint). Onayınızla ben: (a) küçük, test edilebilir PR'ler oluşturup, (b) her PR sonrası `swift build` ve `swift test` çalıştırıp sonucu raporlayacağım.

---

Generated by audit run on 2026-05-02.
