# Performance & Optimization Roadmap (v7.1 - Revised)

Bu döküman, EliteAgent v7.0 "Native Sovereign" vizyonu doğrultusunda, Apple Silicon ve MLX donanım kısıtlarını kullanarak sistem performansını maksimize etme planını (v7.1 revizyonu ile) detaylandırır.

## 1. Metal Level: GPU Komut Trafiği ve Grafik Mühürleme

MLX'in "Lazy Evaluation" ve "Graph Capture" yeteneklerini kullanarak GPU üzerindeki komut yükünü minimize edeceğiz.

### Hedef: %40 Daha Az CPU Overhead
- **`mx.compile` + Fixed-Shape Padding:** `InferenceActor` içindeki `forward` pass, dinamik context uzunluklarında sürekli re-compile tetiklememesi için "Pad-to-Power-of-2" stratejisi ile mühürlenecektir. Bağlam uzunluğu sabit bloklar halinde (örn. 512, 1024, 2048, 4096) compile edilerek gereksiz re-compilation engellenecektir.
- **Lazy Eval Synchronization:** Görselleştirme (`updateSharedBuffer`) ve loglama için tensör içeriklerine erişim, sadece `mx.eval()` sonrasında ve asenkron olarak yapılacaktır. Hot loop içinde senkron `item()` çağrıları yasaklanmıştır.
- **Thermal-Aware Scheduling:** Manuel `MTLCommandQueue` önceliği yerine, macOS termal yönetim sistemiyle uyumlu çalışan dinamik bir önceliklendirme kullanılacaktır.

## 2. Memory Level: Hardware-Native Zero-Copy IPC

UNO (Unified Native Orchestration) mimarisinde "Zero-Copy" prensibini Sandbox bariyerlerini aşacak şekilde uygulayacağız.

### Hedef: Mikrosaniye Seviyesinde IPC Latency
- **IOSurface-backed MTLBuffer:** XPC sınırlarında saf pointer veya ham `Data` paketleri yerine, "IOSurface" tabanlı `MTLBuffer` referansları veya `mach_port` üzerinden paylaşılan bellek bölgeleri kullanılacaktır. Bu, Sandbox ihlali yapmadan cross-process GPU bellek erişimi sağlar.
- **Unmanaged Pointer Management:** Swift'in ARC (Automatic Reference Counting) mekanizmasının XPC tarafındaki işlem bitmeden belleği serbest bırakmaması için `Unmanaged` pointer yönetimi uygulanacaktır.
- **Binary Stream Optimization:** PropertyListEncoder tamamen devre dışı bırakılacak, veriler doğrudan paylaşımlı bellek bölgelerine (shared memory regions) binary olarak yazılacaktır.

## 3. Inference Level: KV-Cache ve Shared Prefix Stratejisi

TTFT (Time to First Token) optimizasyonu için bağlamın dondurulması ve dinamik kuantizasyon uygulanacaktır.

### Hedef: %50 Daha Hızlı 'First Token' Latency (TTFT)
- **Shared Prefix (KV-Cache Frozen State):** EliteAgent'ın değişmez "System Prompt"u için hesaplanan KV-Cache, `KVCache.offset` özelliği kullanılarak dondurulacak (frozen). Her yeni çıkarımda sistem promptu tekrar işlenmeyecek.
- **Dynamic 8-bit Quantization:** 8-bit KV-Cache kuantizasyonu sadece `SystemWatchdog` tarafından belirlenen "Low Memory" (Bellek Baskısı) durumlarında devreye girecektir. Standart modda dikkat (attention) hassasiyetini korumak için 16-bit (Precision) muhafaza edilecektir.

## 4. Revize Uygulama Takvimi (v7.1)

| Aşama | Başlık | Teknik Detay | Öncelik |
|---|---|---|---|
| Phase 1 | Graph Mühürleme | `mx.compile` + Fixed-Shape Padding | **KRİTİK** |
| Phase 2 | KV-Cache Frozen State | Shared Prefix (`KVCache.offset`) entegrasyonu | **YÜKSEK** |
| Phase 3 | Hardware IPC | IOSurface tabanlı Zero-Copy XPC Transport | **ORTA** |
| Phase 4 | Dynamic Quant | Memory-Pressure tabanlı 8-bit KV-Cache | **DÜŞÜK** |

---
**Onaylayan:** EliteAgent Autonomous Architect
**Revizyon:** v7.1 (Hardware-Native Hardware-Aware)

---
**Onaylayan:** EliteAgent Autonomous Architect
**Durum:** Taslak (Draft)
