# EliteAgent — Yazılım Üretim Kuralları (Tüm AI Ajanlar İçin)

Bu dosya hem Claude Code hem de Antigravity (Gemini CLI) tarafından okunur.
**Kurallar mutlaktır. İstisna yoktur. Kural ihlali mimariyi kırar.**

---

## ⛔ KESİN YASAKLAR (ABSOLUTE PROHIBITIONS)

### 1. JSON Yasağı — UNO Kuralı

**Aşağıdaki kodlar `UNOExternalBridge.swift` dışında HİÇBİR DOSYADA yazılamaz:**

```swift
JSONEncoder()           // YASAK
JSONDecoder()           // YASAK
JSONSerialization       // YASAK
.jsonObject(with:       // YASAK
```

**NEDEN?**
EliteAgent, UNO (Unified Native Orchestration) mimarisi üzerine kuruludur. Tüm iç iletişim **binary PropertyList** formatını kullanır. JSON sadece dış protokol sınırında (HTTP sunucusu, Ollama uyumluluğu) kabul edilir.

**2026-05-03'te bu kural ihlal edildi:** Antigravity, üretim kodunda doğrudan `JSONDecoder()` kullandı. Bu, `UNOExternalBridge` üzerinden geçmesi gereken kodu atlattı ve mimari sözleşmeyi bozdu.

**Kullanılması gereken:**
```swift
PropertyListEncoder(outputFormat: .binary)  // seri hale getirme
PropertyListDecoder()                        // çözme
AnyCodable(value)                           // heterojen değerler
```

**İzin verilen tek istisna:**
```swift
// UNOExternalBridge.swift — dış protokol köprüsü
UNOExternalBridge.shared.encode(...)
UNOExternalBridge.shared.decode(...)

// LocalInferenceServer — Ollama uyumlu HTTP katmanı (harici protokol)
// Bu katman JSONEncoder/Decoder kullanabilir çünkü o ZATEN dış protokoldür.
```

---

### 2. DispatchQueue Yasağı

```swift
DispatchQueue.global()   // YASAK
DispatchQueue.main       // YASAK (istisna: FSEventStreamSetDispatchQueue — Apple API zorunluluğu)
DispatchSemaphore        // YASAK
```

**Kullanılması gereken:** `async/await`, `Task`, `TaskGroup`, `actor`, `AsyncStream`

**Belgelenmiş istisna:** `ProjectObserver.swift` içindeki `FSEventStreamSetDispatchQueue` Apple'ın FSEvents API'sinin zorunluluğudur — bu tek istisna DEVLOG'da belgelenmiştir.

---

### 3. Force Unwrap Yasağı

```swift
let x = foo!      // YASAK
foo as! Bar       // YASAK
```

**Kullanılması gereken:** `guard let`, `if let`, `try?`, `as?`

---

### 4. Actor/XPC Sınırlarında Yazısız Sözlük Yasağı

`[String: Any]` ve `[String: AnyObject]` actor veya XPC izolasyon sınırlarını geçemez.
Bunun yerine typed struct, `AnyCodable` veya binary plist kullanın.

---

## 1. Mimari Felsefe

- **Native-First:** Her zaman Apple'ın resmi dokümantasyonuna, Swift 6 standartlarına ve yerel sistem çağrılarına sadık kal.
- **No Middleware:** LangChain, CrewAI veya benzeri soyutlama katmanlarını asla kullanma. Çözümleri yerel kütüphanelerle üret.
- **UNO Protocol:** Aktörler arası iletişim binary PropertyList ve bellek adresleri üzerinden yapılır — asla string veya JSON.
- **Lean Development:** Okunabilir, performanslı, minimum bağımlılıklı kod.

---

## 2. ELM Wiki Operasyon Kuralları

- **Hiyerarşi:** Her zaman `h.md` (Hot Memory) dosyasını oku; şu anki görev ve bağlam orada yatar.
- **Güncellik:** Bir özellik eklendiğinde veya mimari değişiklik yapıldığında, ilgili `wiki/` dosyasını ve `index.md` haritasını anında güncelle.
- **Sorgulama:** Teknik belirsizlik durumunda önce `concepts/` klasörünü kontrol et. Hala eksikse `raw/` klasörüne bak.
- **DEVLOG:** Her tamamlanan görevden sonra `Resources/Config/DEVLOG.md`'ye append et (üzerine yazma).

---

## 3. Kodlama Standartları

- **Swift 6 + Strict Concurrency:** Tüm yeni kod `Sendable`, `actor isolation`, `@MainActor` kurallarına uymalıdır.
- **SwiftUI + Apple Silicon (MLX):** UI için SwiftUI, inference için MLX Swift kullanılır.
- **Dosya Organizasyonu:**
  - `Sources/EliteAgentCore/AgentEngine/` — Orkestrasyon
  - `Sources/EliteAgentCore/LLM/` — Model ve inference
  - `Sources/EliteAgentCore/ToolEngine/` — Araç sistemi
  - `Sources/EliteAgentCore/UNO/` — Binary transport
  - `Sources/EliteAgentCore/Config/` — Yapılandırma
- **Path Yönetimi:** `PathConfiguration.shared.*URL` kullan — asla path hardcode etme.

---

## 4. Teknik Zorunluluklar (Technical Mandates)

- **Metal Backend:** MLX operasyonlarında Lazy Evaluation ve Kernel Fusion prensipleri gözetilmeli. Gereksiz hesaplamalardan kaçın.
- **Memory Anchoring:** Model ağırlıkları ve KV Cache, Unified Memory'de "çivilenmiş" (wired) kabul edilmeli. `WiredBudgetPolicy` ve `WiredMemoryUtils.tune()` kullan.
- **KV Cache:** `maxKVSize = 8192` ile Rotating KV Cache aktif; `kvBits = 4` ile 4-bit kuantizasyon. Bu değerleri değiştirmeden önce test et.
- **Native Context Management:** KV Cache yönetimi, RoPE ve tensor manipülasyonları `MLXLMCommon` standartlarına göre yapılmalı.
- **Speculative Decoding:** `{mainModelURL}-draft` konumunda uyumlu bir draft model varsa otomatik aktive olur.

---

## 5. LLM Intent Sınıflandırması

```
complexity == 1  → Chat/classification → enableThinking = false → hızlı yanıt
complexity > 1   → Planlama/araç kullanımı → enableThinking = true → düşünce bloğu
```

`OrchestratorRuntime.classifyIntent()` bu kararı verir. Lokal model için sistem promptu minimal tutulur.

---

## 6. Araç (Tool) Sistemi Kuralları

- Her araç `ToolUBID` enum'unda bir `case` almalı (önce bu, sonra implementasyon).
- Araçlar `ToolRegistry.shared.register()` ile kayıt edilir.
- İç dispatch UBID ile yapılır, string eşleşmesi ile değil.
- Yeni araç = `ToolIDs.swift`'te yeni case + `Tools/` klasöründe yeni struct.

---

## 7. Test ve Build Gereksinimleri

```bash
swift build          # Her değişiklikten sonra kontrol et
swift test           # Regression testi
```

- Zero Regression politikası geçerlidir.
- Build fail eden kod commit edilmez.
- Swift 6.3.0, macOS 15+, Xcode 16+, Apple Silicon.

---

## Kaynak ve Referans

- Mimari detaylar: `wiki/architecture_deep_dive.md`
- v3 Migration: `wiki/v3_migration_guide.md`
- Performans optimizasyonları: `wiki/performance_optimization_report.md`
- Native Tool Calling: `wiki/native_tool_calling.md`
- Güncel durum: `h.md`
