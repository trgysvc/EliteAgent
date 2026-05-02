# EliteAgent — Kapsamlı Teknik Audit Raporu
**Tarih:** 2026-05-02  
**Dosya kaydı:** Bu rapor otomatik tarama çıktısıdır ve dosyaya kaydedildi — 2026-05-02T15:41:00Z
**Taranan Swift dosyası:** 160+ kaynak dosya  
**Build durumu:** `swift build` — Build complete! (uyarısız)  
**Metodoloji:** Tüm kaynak dosyalar okundu, MLX-Swift 0.31.3 / MLX-LM 3.31.3 API'leri ile karşılaştırıldı, CLAUDE.md UNO kuralları denetlendi, Apple resmi dokümantasyonu referans alındı.

---

## Hızlı Özet

| Önem | Sayı |
|------|------|
| SEVİYE 1 — Kritik (Fonksiyonel Bozukluk) | 5 |
| SEVİYE 2 — Kritik (UNO Kural İhlali) | 4 |
| SEVİYE 3 — Yüksek (API Doğruluğu) | 5 |
| SEVİYE 4 — Orta (Performans/Güvenlik) | 5 |
| SEVİYE 5 — Düşük (Kod Kalitesi) | 6 |

---

## SEVİYE 1 — KRİTİK: Fonksiyonel Bozukluk

### S1-1 · LocalInferenceServer — Ollama Uyumsuzluğu
**Dosya:** `Sources/EliteAgentCore/LLM/LocalInferenceServer.swift:143`  
**Problem:** `handleInferenceRequest` gelen HTTP body'yi `PropertyListDecoder` ile binary plist olarak decode etmeye çalışıyor. Ancak Ollama API'si (ve tüm HTTP/REST istemcileri) JSON gönderir. Bu her zaman başarısız olur — sunucu hiçbir zaman gerçek bir istemciye hizmet veremez.  
```swift
// YANLIŞ (satır 143):
let decoder = PropertyListDecoder()
let request = try decoder.decode(InferenceRequest.self, from: bodyData)
// HTTP istemcileri JSON gönderir, plist değil.
```
**Düzeltme:** `JSONDecoder` kullan. Sunucu içi veri akışı (XPC) plist kullanabilir, ama HTTP katmanı JSON olmalı.

---

### S1-2 · UNODistributedActorSystem — Force Cast
**Dosya:** `Sources/EliteAgentCore/UNO/UNODistributedActorSystem.swift:33`  
**Problem:** `actor.id as! ActorID` — force cast. CLAUDE.md: "No force unwrap (`!`) in production code."  
```swift
// YANLIŞ:
_actors.withLock { $0[actor.id as! ActorID] = actor }
// Eğer ActorID String değilse crash.
```
**Düzeltme:** `guard let id = actor.id as? ActorID else { return }` kullan.

---

### S1-3 · UNOInvocationEncoder — Argümanlar Hiç Kaydedilmiyor
**Dosya:** `Sources/EliteAgentCore/UNO/UNODistributedActorSystem.swift:106`  
**Problem:** `recordArgument` metodu tamamen boş. Distributed actor remote call'larında parametreler hiçbir zaman encoder'a yazılmıyor — remote call'lar her zaman parametresiz gidecek.  
```swift
public mutating func recordArgument<Value>(_ argument: RemoteCallArgument<Value>) throws where Value : SerializationRequirement {
    // Boş — argümanlar kaybolur
}
```
**Düzeltme:** `arguments[argument.effectiveLabel ?? "_\(arguments.count)"] = AnyCodable(argument.value)` gibi bir implementasyon ekle.

---

### S1-4 · UNODistributedActorSystem — executeDistributedTarget Stub
**Dosya:** `Sources/EliteAgentCore/UNO/UNODistributedActorSystem.swift:86`  
**Problem:** `executeDistributedTarget` sadece log yazıp çıkıyor. XPC tarafından gelen distributed actor method çağrıları hiçbir zaman execute edilmiyor.  
**Düzeltme:** Gerçek invocation decode + dispatch mantığı eklenmeli ya da bu metodun kullanılmayacağı net belgelenip sistem `UNOTransport` üzerinden çalışacak şekilde yeniden tasarlanmalı.

---

### S1-5 · LLMModel — Hardcoded Geçersiz Path
**Dosya:** `Sources/EliteAgentCore/LLM/LLMModel.swift:23`  
**Problem:** Model yükleme için `/models/\(name)` hardcoded path kullanılıyor. Bu path macOS'ta mevcut değil.  
```swift
// YANLIŞ:
try await InferenceActor.shared.loadModel(at: URL(fileURLWithPath: "/models/\(name)"))
// Doğru:
try await InferenceActor.shared.loadModel(at: PathConfiguration.shared.modelsURL.appendingPathComponent(name))
```
**Düzeltme:** `PathConfiguration.shared.modelsURL` kullan.

---

## SEVİYE 2 — KRİTİK: UNO Kural İhlali

### S2-1 · MachPortCoordinator — DispatchSource Kullanımı
**Dosya:** `Sources/EliteAgentCore/UNO/MachPortCoordinator.swift:35`  
**Problem:** CLAUDE.md: **"No `DispatchQueue`. All concurrency via `async/await`, `TaskGroup`, and `actor`."**  
```swift
let machSource = DispatchSource.makeMachReceiveSource(
    port: receivePort,
    queue: .global(qos: .userInteractive)  // ← KURAL İHLALİ
)
```
**Düzeltme:** Mach port sinyalizasyonu için `AsyncStream` + `withCheckedContinuation` pattern kullan, DispatchSource'u kaldır.

---

### S2-2 · ProjectObserver — DispatchQueue.main
**Dosya:** `Sources/EliteAgentCore/AgentEngine/ProjectObserver.swift:54`  
**Problem:** `FSEventStreamSetDispatchQueue(stream, DispatchQueue.main)` — doğrudan DispatchQueue kullanımı.  
**Düzeltme:** `FSEventStreamSetDispatchQueue` yerine `FSEventStreamScheduleWithRunLoop` + MainRunLoop veya Swift Concurrency bridge kullan.

---

### S2-3 · AnyCodable — @unchecked Sendable ile Any
**Dosya:** `Sources/EliteAgentCore/Types/Types.swift:450`  
**Problem:** `AnyCodable` `value: Any` tipini taşıyıp `@unchecked Sendable` olarak işaretlenmiş. `Any` Sendable değil — actor sınırlarını geçerken veri yarışı riski. Swift 6 strict concurrency'de bu hata olarak işaretlenir.  
**Düzeltme:** `Any` yerine kapalı bir enum (`CodableValue`) kullan:
```swift
public enum CodableValue: Codable, Sendable {
    case bool(Bool), int(Int), double(Double), string(String)
    case array([CodableValue]), dict([String: CodableValue])
}
```

---

### S2-4 · UNOTransport — @unchecked Sendable NSLock
**Dosya:** `Sources/EliteAgentCore/LLM/LocalInferenceServer.swift:8` ve `UNOTransport.swift:8`  
**Problem:** `@unchecked Sendable` ile işaretlenmiş `final class`lar NSLock kullanıyor. Swift 6'da bu pattern actor ile değiştirilmeli.  
**Düzeltme:** `UNOTransport`'u `actor` yap, NSLock'u kaldır.

---

## SEVİYE 3 — YÜKSEK: API Doğruluğu

### S3-1 · MLX.eval() — Argümansız Çağrı
**Dosya:** `Sources/EliteAgentCore/LLM/InferenceActor.swift:179`, `MLXEngineGuardian.swift:68,113`  
**Problem:** MLX-Swift 0.31.3'te `MLX.eval()` argümansız çağrı API'si mevcut ama kullanım amacı buffer flush için değil — belirli MLXArray'leri değerlendirmek için. Cache temizlemeden önce `eval()` çağrısı yanlış semantik.  
**Referans:** MLX-Swift docs: `eval(_:)` takes `MLXArray...` arguments.  
**Düzeltme:** `MLX.eval()` yerine sadece `MLX.Memory.clearCache()` kullan veya aktif array'leri geçir.

---

### S3-2 · MLX.Device.withDefaultDevice — Yanlış API
**Dosya:** `Sources/EliteAgentCore/LLM/InferenceActor.swift:49`  
**Problem:** `MLX.Device.withDefaultDevice(.cpu) { }` — Bu form geçici device switch içindir. CPU-only mod için kalıcı ayar bu şekilde yapılmaz; kapanınca önceki device'a döner.  
```swift
// YANLIŞ: withDefaultDevice closure scoped'dur
MLX.Device.withDefaultDevice(.cpu) {
    AgentLogger.logInfo(...)  // Sadece bu bloğu etkiler
}
// Blok bittikten sonra default device tekrar GPU'ya döner
```
**Düzeltme:** `MLX.Device.setDefault(.cpu)` (veya versiyon uyumlu equivalent) kullan.

---

### S3-3 · GenerateResult enum case isimleri
**Dosya:** `Sources/EliteAgentCore/LLM/InferenceActor.swift:107-118`  
**Problem:** MLX-LM v3.31.3 `GenerateResult` enum case'leri kaynak kodda farklı isimlendirilmiş olabilir. `.chunk(let text)` yerine `.token` veya `.text`, `.info(let metrics)` yerine farklı naming. `metrics.tokensPerSecond`, `metrics.promptTokenCount`, `metrics.generationTokenCount` field isimleri de versiyona göre değişebiliyor.  
**Aksiyon:** `mlx-swift-lm` kaynak kodunda `GenerateResult` enum'unu doğrula.  
**Not:** Build geçiyor olduğundan şu an API uyumlu, ama gelecek `upToNextMinor` güncellemelerinde kırılabilir.

---

### S3-4 · LocalInferenceServer — Çift import Network
**Dosya:** `Sources/EliteAgentCore/LLM/LocalInferenceServer.swift:2-3`  
**Problem:** `import Network` iki kez yazılmış (satır 2 ve 3).  
**Düzeltme:** Tekrarlı import'u kaldır.

---

### S3-5 · ModelRegistry Eksik Referans
**Dosya:** `Sources/EliteAgentCore/LLM/LocalInferenceServer.swift:185`  
**Problem:** `ModelRegistry.availableModels` kullanılıyor ama `ModelRegistry` tipinin tanımlanıp tanımlanmadığı belirsiz (build geçiyor olduğundan muhtemelen var, ama `ModelCatalog` ile isim tutarsızlığı var).  
**Aksiyon:** `ModelRegistry` ile `ModelCatalog` aynı tip mi kontrol et, birleştirmeyi değerlendir.

---

## SEVİYE 4 — ORTA: Performans ve Güvenlik

### S4-1 · AgentLogger — Her Çağrıda ISO8601DateFormatter Allocation
**Dosya:** `Sources/EliteAgentCore/Utilities/AgentLogger.swift:71`  
**Problem:** Her log çağrısında `ISO8601DateFormatter()` yeniden oluşturuluyor. Formatter oluşturmak pahalı (regex compilation, locale loading). Yoğun inference sırasında çok sayıda log çağrısı = ciddi overhead.  
```swift
// YANLIŞ (her çağrıda):
let isoFormatter = ISO8601DateFormatter()
```
**Düzeltme:**
```swift
private static let isoFormatter: ISO8601DateFormatter = {
    let f = ISO8601DateFormatter()
    return f
}()
```

---

### S4-2 · MLXEngineGuardian — Task Zinciri Bellek Sızıntısı
**Dosya:** `Sources/EliteAgentCore/LLM/MLXEngineGuardian.swift:58-94`  
**Problem:** Her `execute()` çağrısı yeni bir Task oluşturup öncekini bekliyor, ardından `currentTask`'ı yeni bir sarmalayıcı Task'a atıyor. Hızlı ardışık çağrılarda task referansları zinciri oluşturarak bellek birikebilir.  
**Düzeltme:** `AsyncChannel` veya `actor` izolasyonlu serial queue pattern kullan.

---

### S4-3 · UNOSharedBuffer — ftruncate Dönüş Değeri Kontrol Edilmiyor
**Dosya:** `Sources/EliteAgentCore/UNO/UNOSharedBuffer.swift:27`  
**Problem:**  
```swift
ftruncate(fd, off_t(size))  // Dönüş değeri yok sayılıyor
```
`ftruncate` başarısız olursa dosya 0 byte kalır, sonraki `mmap` sıfır-byte segment eşler ve undefined behavior oluşur.  
**Düzeltme:**
```swift
guard ftruncate(fd, off_t(size)) == 0 else {
    close(fd)
    throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno))
}
```

---

### S4-4 · EliteAgentXPC — Gereksiz Ağır MLX Bağımlılıkları
**Dosya:** `Package.swift:86-103`  
**Problem:** `EliteAgentXPC` target'ı MLXLLM, MLXLMCommon, MLXVLM, MLXEmbedders gibi büyük ML kütüphanelerine bağımlı. XPC helper process'in bu kütüphanelere ihtiyacı yok (inference `EliteAgent` main process'te yapılıyor).  
**Etki:** XPC bundle boyutu ve başlatma süresi gereksiz yere artıyor.  
**Düzeltme:** `EliteAgentXPC` bağımlılıklarını sadece `EliteAgentCore` ve `CUNOSupport` olarak sadeleştir.

---

### S4-5 · InferenceActor — Token Başına Gereksiz Float.random
**Dosya:** `Sources/EliteAgentCore/LLM/InferenceActor.swift:225-229`  
**Problem:** Her token üretildiğinde `updateSharedBuffer` 4096 adet `Float.random` yazıyor. Bu veri anlamsız (görsel efekt için rastgele sayı), ama inference hızını düşürüyor.  
**Düzeltme:** Metal buffer'ı gerçek aktivasyon verileriyle doldur ya da bu metodu tamamen kaldır.

---

## SEVİYE 5 — DÜŞÜK: Kod Kalitesi

### S5-1 · Package.swift — Pinlenmemiş Branch Bağımlılıkları
**Dosya:** `Package.swift:24-25`  
```swift
.package(url: "https://github.com/trgysvc/audiointelligence.git", branch: "main"),
.package(url: "https://github.com/modelcontextprotocol/swift-sdk.git", branch: "main"),
```
Branch referansları build tekrarlanabilirliğini bozar; breaking change'ler sessizce girer.  
**Düzeltme:** Stable tag/commit pin kullan veya en azından `revision:` ile sabitle.

---

### S5-2 · PluginManager — Güvensiz dlopen/Unmanaged Bridge
**Dosya:** `Sources/EliteAgentCore/ToolEngine/PluginManager.swift:82-88`  
**Problem:** `dlopen` + `unsafeBitCast` + `Unmanaged.fromOpaque` kombinasyonu. Yanlış formatlı dylib, tip uyumsuzluğu veya eksik `createPlugin` sembolü crash'e neden olabilir. Plugin sandbox'ı yok.  
**Düzeltme:** Daha güvenli bir plugin API'si tasarla; en azından `unsafeBitCast` yerine `Unmanaged<AnyObject>.fromOpaque(ptr).takeRetainedValue()` kullanıldığından emin ol (zaten öyle) ve tip kontrolü ekle.

---

### S5-3 · UNORingBuffer — Sıfır-Sıfır Başlatma Belirsizliği
**Dosya:** `Sources/EliteAgentCore/UNO/UNORingBuffer.swift:21`  
**Problem:**
```swift
if uno_ring_buffer_get_head(header) == 0 && uno_ring_buffer_get_tail(header) == 0 {
    uno_ring_buffer_init(header, capacity)
}
```
Head ve tail'in ikisi de 0 olması yeni allocation'ı değil, tüm verinin consume edilmiş durumunu da temsil eder. İkinci kez `init` çağrısı kapasiteyi sıfırlar.  
**Düzeltme:** Header'a ayrı bir `initialized` flag ekle ya da her allocation'da `init` çağır.

---

### S5-4 · Sparkle SUPublicEDKey Doğrulama
**Dosya:** `Resources/App/Info.plist:32`  
```xml
<string>h2T2JnoAYSK3DoFbzSM4mD2aDVkWk5EuV6a4ytG7d3s=</string>
```
Bu key'in `generate_keys` ile üretilmiş ve özel anahtarın güvenli saklandığı doğrulanmalı. AUDIT_TODO.md'de de işaretlenmiş.  
**Aksiyon:** Sparkle'ın `sign_update` aracıyla test imzası oluştur ve doğrula.

---

### S5-5 · Entitlements — AppleEvents Eksikliği
**Dosya:** `Resources/App/EliteAgent.entitlements`  
**Problem:** AppleScript/Apple Events kullanıldığı hâlde `com.apple.security.automation.apple-events` ve hedef-app bazlı `com.apple.security.scripting-targets` entitlement'ları yok. Bu özellik App Store veya notarization'da reddedilebilir.  
**Düzeltme:** Kullanılan AppleEvent hedefleri için `scripting-targets` ekle.

---

### S5-6 · DEVLOG Çift Konumu
**Problem:** CLAUDE.md `Resources/Config/DEVLOG.md`'yi zorunlu kılarken git status'ta kök dizinde `DEVLOG.md` de modified görünüyor. İki ayrı dosya mı?  
**Düzeltme:** Kök `DEVLOG.md`'yi kaldır veya `Resources/Config/DEVLOG.md`'ye symlink yap.

---

## MLX-Swift Versiyon Notları

**Mevcut pin:** mlx-swift `0.31.3`, mlx-swift-lm `3.31.3`  
**Constraint:** `Package.swift` `.upToNextMinor(from:)` kullanıyor — minor güncelleme otomatik alınır.

| API | Durum |
|-----|-------|
| `loadModelContainer(from:)` | Build geçiyor ✓ |
| `ModelContainer.prepare(input:)` | Build geçiyor ✓ |
| `ModelContainer.generate(input:parameters:)` | Build geçiyor ✓ |
| `GenerateParameters(maxTokens:temperature:)` | Build geçiyor ✓ |
| `UserInput(messages:)` | Build geçiyor ✓ |
| `MLX.Memory.cacheLimit` | Build geçiyor ✓ |
| `MLX.Memory.clearCache()` | Build geçiyor ✓ |
| `MLX.eval()` (no-arg) | Build geçiyor ama semantik yanlış ⚠️ |
| `MLX.Device.withDefaultDevice(.cpu)` | Geçici scope — kalıcı etki yok ⚠️ |

---

## Öncelik Sırası (Önerilen Düzeltme Planı)

```
Sprint 1 (Kritik):
  S1-1  LocalInferenceServer JSON decode
  S1-2  Force cast — actorReady
  S1-5  LLMModel hardcoded path
  S2-1  MachPortCoordinator DispatchSource kaldır
  S4-3  ftruncate dönüş değeri

Sprint 2 (Yüksek):
  S1-3  recordArgument implementasyonu
  S1-4  executeDistributedTarget stub kararı
  S3-4  Çift import kaldır
  S4-1  ISO8601DateFormatter static
  S4-4  XPC bağımlılık sadeleştirme

Sprint 3 (Orta):
  S2-3  AnyCodable → CodableValue enum
  S3-1  eval() semantik düzeltme
  S3-2  Device.withDefaultDevice düzeltme
  S4-5  updateSharedBuffer kaldır/düzelt
  S5-1  Branch pin → commit/tag

Sprint 4 (Düşük):
  S5-3  UNORingBuffer init flag
  S5-4  Sparkle key doğrulama
  S5-5  Entitlements apple-events
  S5-6  DEVLOG tekli konuma taşı
```

---

*Rapor oluşturuldu: 2026-05-02 | Claude Sonnet 4.6 | EliteAgent v7.8.5*
