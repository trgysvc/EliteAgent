# Hot Memory (Güncel Durum) — 2026-05-04

## ACTIVE MISSION: Titan Engine v8.1 Optimizasyonu Tamamlandı

v8.1 sprint'i kapatıldı. Native tool calling, chat latency fix ve 3 performans optimizasyonu (Wired Memory, Rotating KV Cache, Speculative Decoding altyapısı) production'a alındı. Build temiz.

---

## 🎯 TAMAMLANAN (Bu Sprint)

### ✅ Native Tool Calling (Solution A)
- `InferenceActor.generate(tools:enableThinking:)` → `UserInput(tools: toolSpecs)`
- mlx-swift-lm `xmlFunction` formatı → `Generation.toolCall` → `InferenceChunk.toolCall`
- `OrchestratorRuntime`: `handlePlanning()` ToolSpecs üretir, `handleExecution()` native path dispatch eder
- `ToolRegistry.getTool(named:)` ile isim bazlı arama (UBID gereksiz native path'te)
- `MLXProvider.extractThinkBlock()` → `<think>` bloklarını UI'dan gizler

### ✅ Chat Latency Fix
- `enable_thinking: false` → `additionalContext` → Qwen 3.5 `<think>` bloğunu tamamen atlar
- 800 token → ~50 token: ~90s → <10s (13 TPS'de)
- Lokal chat: minimal Türkçe system prompt, `maxTokens=256`, `complexity=1`
- `stripRawMarkdown()` + `stripThinkingOutput()` → temiz UI çıktısı

### ✅ Performans: Rotating KV Cache (Item 5)
- `parameters.maxKVSize = 8192` → `RotatingKVCache` aktif
- Uzun konuşmalarda sınırsız KV büyümesi engellendi

### ✅ Performans: Wired Memory (Item 4)
- Model yüklendikten sonra `WiredMemoryUtils.tune()` arkaplanda çalışır
- `WiredBudgetPolicy` + `WiredMemoryTicket` → her inference sırasında ağırlıklar RAM'de pinlenir
- `makeWiredTicket()` → `container.generate(wiredMemoryTicket:)`

### ✅ Performans: Speculative Decoding Altyapısı (Item 6)
- `draftModelContainer: ModelContainer?` → `{mainModelURL}-draft` otomatik kontrol
- `loadDraftModel(at:)` public API
- `UnsafeTransferBox<T>` (@unchecked Sendable) ile `LMInput` + `LanguageModel` güvenli geçişi
- `MLXLMCommon.generate(draftModel:numDraftTokens:4:)` — aktif olunca 2-4x TPS beklentisi

### ✅ Kural İhlali Düzeltmesi (2026-05-04)
- **Antigravity JSON ihlali** düzeltildi (2026-05-03 ihlalinin ardından)
- `GEMINI.md` (Antigravity), `CLAUDE.md` (Claude Code), `Project_Wiki/rules.md` güncellendi
- JSON yasağı artık her iki AI ajan dosyasında da çok daha açık ve somut örneklerle belirtildi

---

## 🎯 SIRADAKI ADIMLAR

1. **Speculative Decoding Aktivasyonu:** Qwen3 family'den uyumlu 0.5B/1.5B model indir, `-draft` dizinine koy.
2. **Wired Memory Validasyonu:** Logda `📊 [v3-Wired] Budget measured` satırını doğrula.
3. **Kernel Fusion (Phase A):** MLX `mx.compile` + Fixed-Shape Padding (Attention, LayerNorm).
4. **Prefix Sharing (Phase B):** Ortak system prompt için paylaşılan KV Cache pointer.
5. **Qwen 3.5 9B test:** Gerçek agent görevlerinde native tool calling uçtan uca test.

---

## Versiyon ve Durum

| Alan | Değer |
|---|---|
| Versiyon | v8.1 "Titan Optimized" |
| Model | Qwen 3.5 9B (qwen-3.5-9b-4bit) |
| Build | ✅ Temiz (swift build) |
| Araç Sayısı | 38 (UBID ile kayıtlı) |
| Native Tool Calling | ✅ Aktif (Qwen xmlFunction) |
| Chat Latency | <10s (enable_thinking=false) |
| KV Quantization | 4-bit, group=64, start=256 |
| KV Cache | Rotating (8192 token window) |
| Wired Memory | ✅ Altyapı hazır |
| Speculative Decoding | 🟡 Altyapı hazır, draft model gerekli |

---

## Kritik Mimari Kararlar

### JSON Kuralı (UNO)
- `JSONEncoder`/`JSONDecoder` → SADECE `UNOExternalBridge.swift` içinde
- İç veri → `PropertyListEncoder(outputFormat: .binary)` veya `AnyCodable`
- Bu kural **2026-05-03'te** Antigravity tarafından ihlal edildi. Düzeltildi.

### enableThinking Mantığı
```
complexity == 1  →  enableThinking = false  →  chat/classification (hızlı)
complexity > 1   →  enableThinking = true   →  planning/tools (düşünme)
```

### Native vs. Legacy Tool Dispatch
- **Native path:** `CompletionResponse.toolCalls` varsa → `ToolRegistry.getTool(named:)`
- **Legacy path:** ThinkParser → `CALL([UBID]) WITH {...}` → UBID lookup
- Lokal model: native path. Cloud model: legacy path (UBID tabanlı).

---

## Öğrenilmiş Dersler (Bu Sprint)

- **enable_thinking=false** kritik: mlx-swift-lm'nin `additionalContext["enable_thinking": false]` API'si `<think>` bloğunu üretimden tamamen keser. Sonradan strip etmek yerine hiç üretmemek doğru yaklaşım.
- **System prompt sessiz hata:** `InferenceActor.generate()` başlangıçta system mesajını hiç eklemiyordu. `mlxMessages.insert` ile düzeltildi.
- **UnsafeTransferBox:** MLXLMCommon'ın package-internal `SendableBox` deseni gerektiğinde kopyalanabilir. @unchecked Sendable sarmalayıcısı, değer tiplerinin @Sendable closure'lara geçişini sağlar.
- **AI ajan kuralları:** Yazılı kural olması yetmez. Kural dosyasının (GEMINI.md, CLAUDE.md) ilk satırlarında, somut kod örnekleriyle, "bu kural ihlal edildi" notu ile belirtilmesi gerekiyor.
