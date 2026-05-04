# Performans Optimizasyonları — Uygulama Raporu (v8.1)

**Uygulama Tarihi:** 2026-05-04  
**Durum:** Production-ready, build temiz

---

## Özet

v8.1 aşamasında `InferenceActor.swift`'te üç temel performans optimizasyonu uygulandı. Bu optimizasyonlar sırasıyla: sohbet gecikmesi, bellek yönetimi ve çıkarım hızı sorunlarını ele alır.

---

## Item 5 — Rotating KV Cache (maxKVSize)

**Uygulama:** `InferenceActor.generate()` içinde `GenerateParameters` bloğuna eklendi.

```swift
parameters.maxKVSize = 8192
```

**Etki:**
- MLX, `KVCacheSimple` yerine `RotatingKVCache` kullanır.
- 8192 token sonrası eski girişler (ilk 4 token korunur) silinir.
- Uzun ajan döngülerinde sınırsız KV büyümesini önler.
- Hiçbir kod yolu değişmez — tek satır.

**Trade-off:** 8192 tokenden uzun bağlamlar, eski kısmı "unutur". Bu, çoğu sohbet ve tek görev için önemsizdir. Çok uzun araştırma görevleri için `maxKVSize = 16384` denenebilir.

---

## Item 4 — Wired Memory (WiredBudgetPolicy)

**Uygulama:** `loadModel()` sonrası arkaplan görevi + her `generate()` çağrısında bilet oluşturma.

### Ölçüm (Background Task)

```swift
Task { [container] in
    let measureParams = GenerateParameters(maxTokens: 32, temperature: 0.6)
    let m = try await container.perform { ctx in
        try await WiredMemoryUtils.tune(context: ctx, tokenCount: 64, parameters: measureParams)
    }
    self.wiredMeasurement = m
    // m.weightBytes, m.kvBytes, m.workspaceBytes → log
}
```

`WiredMemoryUtils.tune()` 64 token ile gerçek bir prefill geçişi yapar ve gerçek bellek değerlerini ölçer. Tahmini değil.

### Bilet Oluşturma (Her generate() çağrısında)

```swift
private func makeWiredTicket() -> WiredMemoryTicket? {
    guard !isCPUOnly, let m = wiredMeasurement else { return nil }
    let policy = WiredBudgetPolicy(baseBytes: m.weightBytes + m.workspaceBytes, id: wiredPolicyID)
    return policy.ticket(size: m.kvBytes, kind: .active)
}
```

`wiredPolicyID: UUID` sabittir — aynı policy grubu altında biletler toplanır.

### Kullanım

```swift
let wiredTicket = self.makeWiredTicket()
let resultStream = try await container.generate(
    input: input, 
    parameters: parameters, 
    wiredMemoryTicket: wiredTicket
)
```

`ModelContainer.generate()` bilet aldığında `WiredMemoryTicket.withWiredLimit { }` ile inference süresince limit'i korur.

**Etki:**
- Model ağırlıkları RAM'de pinlenir → ilk token gecikmesi düşer.
- M-serisi çiplerde `mlx_set_wired_limit()` çağrılır (Metal destekleniyorsa).
- CPU-only modda otomatik devre dışı kalır (`isCPUOnly` kontrolü).
- Ölçüm henüz tamamlanmamışsa (`wiredMeasurement == nil`) ticket olmadan devam eder — graceful degradation.

---

## Item 6 — Speculative Decoding (Draft Model)

**Uygulama:** `InferenceActor`'a draft model desteği eklendi. Infrastructure tam; aktivasyon opt-in.

### Yeni Property ve API

```swift
private var draftModelContainer: ModelContainer? = nil

// Otomatik yükleme: {mainModelURL}-draft dizini varsa
private func tryLoadDraftModel(for mainModelURL: URL) async

// Manuel yükleme
public func loadDraftModel(at url: URL) async throws
```

### Otomatik Yükleme Mantığı

```swift
// Model yüklendikten sonra:
Task {
    await self.tryLoadDraftModel(for: url)
}
// url.lastPathComponent + "-draft" dizini kontrol edilir
// Varsa loadModelContainer(from:) ile yüklenir
```

Örnek: Ana model `Models/qwen-3.5-9b-4bit` ise, `Models/qwen-3.5-9b-4bit-draft` dizini kontrol edilir.

### Speculative Decode Yolu

```swift
if let draftContainer = self.draftModelContainer {
    let draftBox = await draftContainer.perform { ctx in
        UnsafeTransferBox<any LanguageModel>(ctx.model)
    }
    let inputBox = UnsafeTransferBox(input)
    resultStream = try await container.perform { mainCtx -> AsyncStream<Generation> in
        try MLXLMCommon.generate(
            input: inputBox.take(),
            parameters: parameters,
            context: mainCtx,
            draftModel: draftBox.take(),
            numDraftTokens: 4,
            wiredMemoryTicket: wiredTicket
        )
    }
}
```

### UnsafeTransferBox Pattern

```swift
private final class UnsafeTransferBox<T>: @unchecked Sendable {
    var value: T?
    init(_ value: T) { self.value = value }
    func take() -> T { defer { value = nil }; return value! }
}
```

MLXLMCommon'ın kendi `SendableBox` (package-internal) deseniyle aynı yaklaşım. `LMInput` ve `LanguageModel` Swift 6 strict concurrency sınırlarını `@unchecked Sendable` sarmalayıcıyla geçer. Güvenlidir çünkü:
1. `LMInput` tek bir kez tüketilir (move semantics)
2. `LanguageModel` ağırlıkları `eval()` sonrası salt okunurdur — eşzamanlı okuma güvenlidir
3. KV cache'ler her inference için ayrıdır — paylaşım yoktur

### Beklenen Etki

| Senaryo | Beklenen Hız Artışı |
|---|---|
| Qwen3-0.5B draft + Qwen3.5-9B main | 2-4x TPS |
| Greedy decoding (temperature=0) | En yüksek kabul oranı |
| Yüksek entropi (temperature=0.7+) | Daha düşük kabul oranı |

**Not:** Speculative decoding **tokenizer uyumluluğu** gerektirir. Draft model ve main model aynı tokenizer ailesinden olmalı. Farklı aile modeller kullanılırsa sonuçlar bozulur.

---

## Tam GenerateParameters Yapılandırması (v8.1)

```swift
var parameters = GenerateParameters(maxTokens: maxTokens, temperature: 0.6)
parameters.repetitionPenalty = 1.15      // tekrar cezası
parameters.repetitionContextSize = 64   // 64 token pencere
parameters.kvBits = 4                   // 4-bit KV kuantizasyonu
parameters.kvGroupSize = 64             // kuantizasyon grup boyutu
parameters.quantizedKVStart = 256       // 256 token sonrası kuantizasyon başlar
parameters.topP = 0.9                   // nucleus sampling
parameters.minP = 0.05                  // minimum prob eşiği
parameters.maxKVSize = 8192             // Rotating KV Cache penceresi (Item 5)
```

---

## Önceki Performans Sorunları ve Çözümleri

| Sorun | Kök Neden | Çözüm |
|---|---|---|
| "merhaba" yanıtı 90 saniye | `<think>` bloğu 800+ token üretiyor | `enable_thinking: false` → `additionalContext` |
| `**` ve `*` karakterler UI'da görünüyor | Model markdown formatlıyor | `stripRawMarkdown()` sadece lokal chat için |
| "Thinking Process:" UI'ya sızıyor | `[RULE: ...]` formatlı prompt yapısal çıktı tetikledi | `stripThinkingOutput()` + minimal Türkçe system prompt |
| Repetitive `!!!!` karakterleri | `<think>` bloğu bitmeden repetition | `repetitionPenalty=1.15, repetitionContextSize=64` |
| System prompt sessizce görmezden gelindi | `InferenceActor.generate()` hiç eklemiyordu | `mlxMessages.insert(systemMessage, at: 0)` |
| Sınırsız KV büyümesi | `KVCacheSimple` sınırsız büyüme | `maxKVSize=8192` → `RotatingKVCache` |

---

## Sonraki Adımlar

1. **Draft Model İndirme:** Qwen3 family'den uyumlu 0.5B veya 1.5B model `mlx-community` üzerinden indir, `-draft` dizinine yerleştir.
2. **Wired Memory Validasyonu:** `📊 [v3-Wired] Budget measured` log satırını logda doğrula.
3. **Kernel Fusion:** MLX `mx.compile` ile Attention ve LayerNorm optimizasyonu (Phase A).
4. **Prefix Sharing:** Ortak system prompt için paylaşılan KV Cache pointer (Phase B).
