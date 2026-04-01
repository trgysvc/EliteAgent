# 🛸 EliteAgent: Master Feature Audit (Kapsamlı Özellik Listesi)

Bu döküman, EliteAgent projesinin ilk satırından son satırına kadar tüm kaynak kodlarının, `devlog.md` kayıtlarının ve `Sources/` dizinindeki tüm araçların (Tools) ve motorların (Engines) taranmasıyla oluşturulmuş **nihai** listedir.

## 1. Mimari ve Altyapı (System Architecture)
- **XPC Microservices Engine**: Ana uygulamanın arayüzünü dondurmamak için `EliteAgentXPC` servisi üzerinden asenkron işlem yürütme.
- **Framework-First Implementation**: Tüm mantığın `EliteAgentCore` framework'ünde toplanarak yüksek hızda derlenmesi.
- **Sparkle Auto-Update (v14.0+)**: Uygulamanın arka planda otonom olarak kendi güncel versiyonlarını takip etmesi ve yüklemesi.
- **Sandbox-Free OS Integration**: Tam dosya sistemi ve shell yetkisi (App Sandbox devredışı), Enterprise seviyesi yetkilendirme.
- **HIG Compliance Logic**: Apple Human Interface Guidelines'a %100 uyumlu dosya hiyerarşisi (`PathConfiguration`).
    - `Application Support`: `~/Library/Application Support/EliteAgent`
    - `Logs`: `~/Library/Logs/EliteAgent`
    - `Caches`: `~/Library/Caches/EliteAgent`
- **SignalBus (Priority Management)**: `.critical`, `.high` ve `.normal` öncelikli işlem kuyrukları.

## 2. Titan Yerel Zeka (Intelligence Layer)
- **MLX Local Provider**: Apple Silicon (NPU/GPU) üzerinde çalışan `InferenceActor` ile tamamen internetten bağımsız çıkarım (Offline Intelligence).
- **4-bit Quantization Support**: Llama, Phi ve Mistral modelleri için optimize edilmiş GPU bellek kullanımı.
- **Hybrid Reasoning (Cloud/Local)**: Intent Classification (Niyet Sınıflandırma) ile görevin karmaşıklığına göre en uygun modele geçiş.
- **RAG Memory Bridge**: `MemoryAgent` ve `MemoryTool` ile geçmiş deneyimlerin (Store Experience) kalıcı hafızaya alınması.
- **Qwen 2.5 Engine (7B-4bit)**: M4-optimized NPU/GPU native yerel SLM entegrasyonu.
- **ChatML Template Engine**: Qwen-specific prompt formatlama ve akıllı context yönetimi.

## 3. Görsel ve Teknik Sunum (Visualizers)
- **Neural Sight (Metal Engine)**: AI'nın her bir düşünce katmanını 3D Point Cloud (nokta bulutu) olarak 120 FPS'te canlandıran Metal Shader'ları.
- **Triple-Buffering Logic**: CPU ve GPU arasında 0-latency (race-condition free) veri senkronizasyonu.
- **Semantic Awaken States**: Yükleme sırasında (Pulse/Gather/Glow) görsel durum geri bildirimi.
- **vDSP Dynamic Waveform**: Apple Accelerate kullanarak akışkan, gradyanlı ve yüksek çözünürlüklü ses dalgası görselleştirmesi.
- **Röntgen Card UI**: Adli ve biyolojik ses verilerini glassmorphism efektiyle sunan SwiftUI-native analiz kartı.

## 4. Donanım Koruma ve İzleme (Safety & Health)
- **Hardware Protection Shield**: İşlemci aşırı ısındığında GPU yükünü (visualizer) azaltan otonom refleks sistemi.
- **Thermal Watchdog**: `ProcessInfo.thermalState` verilerinin saniyelik takibi ve termal dalgalanma uyarısı.
- **Memory Pressure Manager**: RAM şişmelerinde (özellikle SLM kullanımı sırasında) "Zarif Geri Çekilme" (Graceful Degradation) protokolleri.
- **Prompt Sanitizer**: Kullanıcı ve sistem arasındaki tüm veri akışında PII (Kişisel veri) ve API anahtarı sızma koruması.
- **Adaptive Thermal Throttling**: NPU/GPU üretimi sırasında `serious` ve `critical` ısı durumlarında akıllı yavaşlatma.
- **Memory-Efficient Integrity Shield**: 5GB+ ağırlıkların 64MB chunked SHA-256 ile güvenli doğrulanması.

## 5. Universal Tool Ecosystem (Araç Seti)
- **Dosya ve Döküman (High-Speed I/O)**:
    - `WriteFileTool`: Mutlak yol (absolute path) ve tilde (~) desteğiyle güvenli yazma.
    - `ReadFileTool`: PDF (PDFKit), DOCX (textutil) ve Markdown operasyonları.
- **Otonom Kodlama ve Git**:
    - `PatchTool`: Atomik ve diff-tabanlı kod düzeltme (context korumalı).
    - `GitTool`: Kod tabanında otonom `status`, `diff`, `commit` ve `revert` yetenekleri.
- **İletişim ve Otomasyon (System Protocols)**:
    - **WhatsApp Otonom Mesajlaşma**: `MessengerTool` üzerinden UI otomasyonu ile mesaj gönderimi.
    - **Apple Mail & Calendar**: `apple_mail` ve `apple_calendar` araçlarıyla doğrudan sistem randevu ve e-posta kontrolü.
    - **MediaController**: Apple Music arama, çalma ve sistem ses kontrolü.
- **Web Zekası**:
    - `BraveSearch`: Brave Search API üzerinden güncel, doğru ve reklamsız dünya bilgisi.
    - `WebFetch`: Dinamik HTML sayfalarını okuyup otonom olarak Markdown'a çevirme.
- **Vision (Bilgisayarlı Görü)**:
    - `ImageAnalysisTool`: Apple Vision framework ile ekran/dosya OCR ve UI koordinat çıkarma.

## 6. Music DNA: Biologic MIR Engine (EliteMIR)
- **Spectral DNA (DSP Core)**:
    - `STFTEngine`: Zaman-Frekans dönüşümü (Short-Time Fourier Transform).
    - `MelFilterBank`: İnsan kulağına göre kalibre edilmiş 128-band Mel Spectrogram.
    - `CQTEngine`: Müzikal notalara duyarlı Constant-Q Transform.
    - **Chroma CENS (v7.1)**: Kapak şarkısı ve değişim tespiti için enerji-normalize harmonik parmak izi (L1-Smooth-L2).
- **Analysis Modules**:
    - `YINEngine`: Hassas Pitch (perde) takibi ve ton tespiti.
    - `HPSSEngine`: Harmonik ve Perküsif (vokal vs beat) ayrıştırma.
    - `MFCCEngine`: Ses tınısını (timbre) belirleyen ilk 20 katsayı.
    - `Onset/RhythmEngine`: BPM, Beat grid ve vuruş tutarlılık analizi.
    - **Multi-Band PLP (v7.1)**: Çok bantlı (Sub/Low/Mid/High) predominant local pulse tahmini.
    - `StructureEngine`: Şarkının bölümlerini (Verse, Chorus, Bridge) tespit eden segmentasyon.
- **Forensic Röntgen (Evidence)**:
    - `ForensicDNAEngine`: Dosya kaynağı (WhereFroms), dijital imzalar ve kodlayıcı tespiti.
- **AI Works Center**: Raporların `~/Documents/AI Works` klasöründe profesyonel PDF/MD/JSON olarak arşivlenmesi.

---
*EliteAgent Core · Version 7.1 Master List · April 2026*
