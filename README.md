# 🛸 EliteAgent

<p align="center">
  <b>Masaüstünüzde çalışan, tam otonom ve donanım duyarlı (Hardware-Aware) Hibrit Yapay Zeka Ajanı.</b><br>
  <i>Apple Silicon (M-Serisi) için özel olarak inşa edilmiş, "Titan" mimarisini barındıran uçtan uca zeka köprüsü.</i>
</p>

---

## 📖 Proje Hakkında
**EliteAgent**, yalnızca metin (text) işleyen standart bir LLM (Büyük Dil Modeli) istemcisinden öte, macOS işletim sistemine tamamen entegre olmuş, kendi alt-ajanlarını (Subagents) eğitebilen, terminal çalıştırabilen, web ortamında gezinebilen ve hatta sistem donanımınızın durumuna göre "zarif geri çekilme" (Graceful Degradation) yapabilen **hibrit bir zeka (Hybrid Intelligence) aracıdır.**

EliteAgent, "Cloud" (Bulut - OpenRouter) üzerindeki en son sınır modellerinin analitik yeteneklerini, Apple M-Serisi GPU ve NPU gücüne sahip yerel SLM'lerin (Small Language Models) hızı ve gizliliği ile birleştirir.

## 🔥 Temel Özellikler

### 1. Titan Mimarisi (Görsel & Yerel Zeka)
- **Offline Brain (MLX Yerel Çıkarım):** Sistem, `InferenceActor` üzerinden **4-bit Quantization** uygulanmış MLX modellerini (Örn: Llama-3-8B veya Phi-3) asenkron çalıştırabilir. Ağ bağlantısı tamamen kesik olsa bile muhakeme, planlama ve kod analizini hızla gerçekleştirebilir.
- **Neural Sight (Metal Engine):** EliteAgent sadece düşünmez; düşündüğü süreci size gösterir. `NeuralSight.metal` üzerinden gelen tensör verileri kopyalanmadan (**Zero-Copy** / `MTLStorageModeShared`) GPU'ya ulaştırılarak arka planda 120 FPS akıcılığında bir nokta bulutu (Point Cloud) vizyonu sunar.

### 2. Donanım Koruma Kalkanı (Hardware Protection Reflex)
- **System Watchdog:** Ajan, donanımla sürekli konuşur. Terminal kodlarından `ProcessInfo.thermalState` ve `MemoryPressure` takibini saniyelik bazda yürütür.
- **Öncelikli Sinyal Kanalı (SignalBus):** Bir donanım baskısı yaşandığında, ajanın iç iletişim ağı olan `SignalBus` hemen "Kritik" (Critical) şeridi devreye sokarak önemsiz işlemleri dondurur ve donanımı dinlendirir. (Layout hatalarını durdurur, görsel yoğunluğu azaltır).

### 3. Kapsamlı Evrensel Araç Seti (Tool Ecosystem)
Kendi kendine görev atayıp otonom şekilde çözen Planner yapısı sayesinde EliteAgent, onlarca aracı zekice yönetir:
- **PatchTool & WriteFileTool:** Büyük dosyaların sadece gereken satırlarını (diff) bulan ve context sınırlarını aşmadan "atomik yama" yapabilen kodlama araçları.
- **Git State Engine (GitTool):** Kendiliğinden repo commit'leyen, status okuyan veya yanlış yaptığında revert atabilen izole sürüm kontrol aracı.
- **Brave Search & Web Fetch:** İnterneti canlı tarayan, DuckDuckGo API'si yerine `Brave API` ile derin okuma yapan ve sayfaları Markdown formatına (strukturize) temizleyerek okuyan bilgi işleyiciler.
- **Image Analysis (Vision):** Resimleri parçalayan, içlerindeki UI (Arayüz) koordinatlarını ve metinlerini (OCR) idrak edebilen görsel analiz.
- **Experience Vault (MemoryTool):** Eskiden çözdüğü devasa algoritmaları L2 veritabanına kaydeden, benzer görevlerde "Cloud'a" sormadan geçmişten çağırabilen (RAG) hafıza sistemi.
- **Subagent & Ecosytem (Apple HIG):** Kendini çoklayabilen, görevleri bölüştürebilen alt-ajanlar. (WhatsApp üzerinden otonom mesaj gönderimi, UI/UX etkileşimi vb.).

### 4. IPC & Modülerlik (Security & Autonomy)
- **Sandbox'ın Yıkılması:** Apple'ın kısıtlayıcı App Sandbox yapısı kırılarak ajana diskte gerçek bir "Mühendis" yetkileri verildi (Full File I/O + Shell erişimi).
- Proje `App`, `EliteAgentCore` (Framework) ve XPC Service olarak **3 lü mikro-mimariye** parçalandı, `readLine` veya UI tıkanıklıkları (ViewBridge hataları) önlendi.

---

## ⚙️ Kurulum & Derleme (Installation & Build)

EliteAgent, Apple'ın en modern standartlarını (`Swift 6`, `@MainActor`, `Sendable`) kullanarak derlenmektedir.

### Gereksinimler
- **İşletim Sistemi:** macOS 14.0 (Sonoma) veya üzeri.
- **İşlemci:** Apple Silicon (M1/M2/M3/M4 vb.).
- **Bellek:** 16GB veya üzeri RAM (Lokal "Titan" SLM mimarisi Unified Memory için).
- **Geliştirme Ortamı:** Xcode 15 veya üzeri.

### Projeyi Ayağa Kaldırma

1. Üçüncü Parti `API Key` Kurulumları:
   - Projenin `VaultManager` dosyası `OPENROUTER_API_KEY` ve `BRAVE_API_KEY` bilgilerini doğrudan **Keychain** (veya Vault.plist) içerisinden okur. Bu anahtarları sisteme tanıtmalısınız.

2. Hibrit SPM (Swift Package Manager) Ayarı:
   EliteAgent hem Xcode Uygulama Çerçevesine (Sandbox/Signing için) hem de SPM modüllerine ihtiyaç duyar.
   - Projeyi `EliteAgent.xcodeproj` dosyasına çift tıklayarak **Xcode** üzerinden açın.
   - `MLX`, `MLXNN` ve `MLXRandom` paket ürünlerinin `EliteAgentCore` hedefine (`Frameworks, Libraries, and Embedded Content` sekmesinden) bağlı olduğundan emin olun.
   - Gerekirse `File > Packages > Reset Package Caches` ile SPM'i temizleyin.
   
3. Çalıştırma:
   - `Cmd + B` ile build doğrulamasını yapın.
   - `Cmd + R` ile UI penceresini (ChatWindowView) ve Metal tabanlı Neural Visualizer katmanını başlatabilirsiniz.

---

## 📂 Proje Mimarisi

```
EliteAgent/
├── App/                       # Xcode SwiftUI Arayüzü (ChatWindowView)
├── Sources/
│   ├── elite/                 # Saf Command-Line (CLI) Yönetim Noktası
│   └── EliteAgentCore/        # EliteAgent'in Beyni ve Çekirdeği
│       ├── Agents/            # Orchestrator, Planner, Critic, Subagents
│       ├── ToolEngine/        # Patch, Shell, Fetch, WebSearch vs.
│       ├── UI/                # MTKView, NeuralSight.metal (Görselleştirme)
│       ├── LLM/               # InferenceActor (Local), CloudProvider (OpenRouter)
│       └── Security/          # VaultManager, PromptSanitizer, Sentinel
├── devlog.md                  # Gün gün detaylı "Mimari Gelişim" tarihçesi.
└── Package.swift              # SPM Modulasyonları (MLX, vs.)
```

---

## 🚦 Bilinen Limitasyonlar & Öneriler
- **Increased Memory Limit OOM Uyarısı:** Yerel modelleri ayağa kaldırmak için projenin `EliteAgent.entitlements` dosyası `com.apple.developer.kernel.increased-memory-limit` izni istemektedir. 8GB makinelerde bu izin kullanılsa bile Neural Sight (Metal) görselliği kısıtlı çalışabilir.
- **TCC İzinleri:** Ajanın WhatsApp/iMessage gönderimi veya UI elementlerini otonom (Automation) tıklayabilmesi için `Sistem Ayarları > Gizlilik ve Güvenlik > Erişilebilirlik ve Otomasyon` izinlerini uygulamanıza manual olarak vermeniz gerekir.

---

> *"Privacy by Design. Autonomy by Nature."*  
> **[EliteAgent Core - v5.3]**
