# ELITE AGENT — Proje Tasarım Dokümanı (PRD)

**Versiyon:** 5.2-elite
**Platform:** macOS (Apple Silicon — M serisi)
**Dil:** Swift 6
**Durum:** 🟡 Development / Mimari İnşa Aşaması
**Tarih:** 21 Mart 2026
**Hedef Kitle:** Sound Architect & Elite Developer

---

> ⚠️ **HALLÜSINASYON ENGEL PROTOKOLÜ**
> Bu doküman ground-truth kaynaktır. Hiçbir AI ajanı veya geliştirici bu dokümanda açıkça tanımlanmayan hiçbir özelliği varsayım yaparak implemente edemez. Belirsiz bir durum için önce bu doküman güncellenmeli, sonra kod yazılmalıdır.
> **Kural:** `"Muhtemelen şöyle çalışır"` → geçersiz. `"Dokümanda X bölümünde yazıyor"` → geçerli.

---

---

## Revizyon Notu (v5.1 → v5.2)

| Değişiklik | Madde | Açıklama |
|------------|-------|----------|
| `chrome-mcp` kaldırıldı | Madde 11.2 | npm bağımlılığı; Safari + WebKit ile karşılanıyor |
| BrowserAgent eklendi | Madde 13.6 (yeni) | Safari + WebKit native tarayıcı otomasyonu |
| CUA bölümü güncellendi | Madde 13.1 | Safari AXUIElement + WebKit ikili katman |
| Görev kategorisi güncellendi | Madde 3.2 | "Chrome navigasyon" → "Safari/web otomasyonu" |
| vault.plist güncellendi | Madde 19 | chrome-mcp kaldırıldı; browser bloğu eklendi |
| Proje yapısı güncellendi | Madde 20.1 | Browser/ dizini eklendi |
| Yapım takvimi güncellendi | Madde 21 | chrome-mcp maddeleri → BrowserAgent |

---

## Revizyon Notu (v5.0 → v5.1)

| Değişiklik | Madde | Açıklama |
|------------|-------|----------|
| Kullanım Profilleri | Madde 6.1 | Local-First, Cloud-Only, Hibrit — üç profil tanımlandı |
| OpenRouter desteği | Madde 6.4, 6.5 | OpenRouter provider tipi + model path formatı |
| Dynamic Downscaling | Madde 6.8 (yeni) | RAM baskısına ve kullanıcı aktivitesine göre otomatik model küçültme |
| Donanım model önerisi | Madde 6.9 (yeni) | M serisi chip başına hangi modelin çalışacağı tablosu |
| Privacy Guard Cache | Madde 7.6 (yeni) | Tekrarlayan payload için Guard sonucunu önbellekle |
| Privacy Guard cloud-only modu | Madde 7.1, 7.7 (yeni) | Local model yokken PRIVACY_BLOCK davranışı |
| Actor Deadlock Prevention | Madde 5.6 (yeni) | Sinyal timeout + döngüsel bağımlılık kuralları |
| Gereksinimler tablosu | Madde 20.4 | Chip bazlı RAM gereksinimleri gerçekçi değerlere güncellendi |
| AXUIElement kırılganlık notu | Madde 13.5 (yeni) | Identifier değişimi riski ve fallback stratejisi |

---

1. [Platform Kararı & Stratejik Gerekçe](#1-platform-kararı--stratejik-gerekçe)
2. [Proje Vizyonu & Felsefe](#2-proje-vizyonu--felsefe)
3. [Hedef Kitle & Kullanım Senaryoları](#3-hedef-kitle--kullanım-senaryoları)
4. [Yazılım Katman Mimarisi](#4-yazılım-katman-mimarisi)
5. [Ajan Mimarisi — Swift Actor Modeli](#5-ajan-mimarisi--swift-actor-modeli)
6. [LLM Inference Katmanı — Harpsichord Bridge](#6-llm-inference-katmanı--harpsichord-bridge)
7. [Privacy Guard — Veri Gizlilik Katmanı](#7-privacy-guard--veri-gizlilik-katmanı)
8. [Teknik Stack — Swift Native-First](#8-teknik-stack--swift-native-first)
9. [Sinyal Sözleşmeleri](#9-sinyal-sözleşmeleri)
10. [Tool Engine — Araç Sistemi](#10-tool-engine--araç-sistemi)
11. [MCP Gateway](#11-mcp-gateway)
12. [Git State Engine](#12-git-state-engine)
13. [CUA & BrowserAgent — AXUIElement + WebKit](#13-cua--browseragent--axuielement--webkit)
14. [Görev Döngüsü & Kullanıcı Etkileşimi](#14-görev-döngüsü--kullanıcı-etkileşimi)
15. [Hafıza Mimarisi — L1/L2 + Privacy Split](#15-hafıza-mimarisi--l1l2--privacy-split)
16. [Yetenek Tanımları — Skill Engine](#16-yetenek-tanımları--skill-engine)
17. [AI Entegrasyonu — The Thinking Protocol](#17-ai-entegrasyonu--the-thinking-protocol)
18. [Güvenlik & Sandbox — XPC](#18-güvenlik--sandbox--xpc)
19. [Konfigürasyon — vault.plist](#19-konfigürasyon--vaultplist)
20. [Kurulum & Dağıtım](#20-kurulum--dağıtım)
21. [Yapım Takvimi](#21-yapım-takvimi)
22. [Runbook — Operasyonel Hata Giderme](#22-runbook--operasyonel-hata-giderme)
23. [Ajan-Araç Yetki Matrisi](#23-ajan-araç-yetki-matrisi)
24. [Gelecek Vizyon](#24-gelecek-vizyon)

---

## 1. Platform Kararı & Stratejik Gerekçe

### 1.1 Karar

Elite Agent **yalnızca macOS** için geliştirilir. Hedef donanım **Apple Silicon M serisi** işlemcilerdir. Başka platform desteği planlanmamaktadır.

### 1.2 Stratejik Gerekçe

| Kriter | Değerlendirme |
|--------|---------------|
| **Rakip ortamı** | Linux/Windows ajan ekosistemi kalabalık; OpenClaw, OpenHands, Eigent, Claude Code hepsi bu platformlarda güçlü. macOS native ajan alanı fiilen boş. |
| **Hedef kitle uyumu** | Xcode + Figma + Final Cut kullanan Apple geliştirici ve kreatif profesyonel profili Elite Agent'ın MCP entegrasyonlarıyla mükemmel örtüşüyor. |
| **Donanım avantajı** | M serisi Unified Memory: R1-32B model dizüstü bilgisayarda çalışıyor. Rakiplerin büyük çoğunluğu cloud-first çünkü local inference bu kadar erişilebilir değil. |
| **Native API erişimi** | AXUIElement (CUA), XPC (sandbox), launchd (daemon), Core ML, MLX — bu API'ler yalnızca macOS native uygulamalara açık. Electron veya web tabanlı rakipler bu derinliğe ulaşamıyor. |
| **Odak** | Tek platformda gerçekten derin gitmek, üç platformda yüzeysel kalmaktan daha değerli. |

### 1.3 Stratejik Gerekçe Özeti

Elite Agent macOS only ve Apple Silicon native seçimi; rekabetsiz alanda derin uzmanlaşma, M serisi Unified Memory avantajı, AXUIElement + XPC + MLX gibi yalnızca native uygulamalara açık API'ler ve Apple geliştirici kitlesinin iş akışıyla tam örtüşme üzerine kurulmuştur. Bu karar kalıcıdır.

---

## 2. Proje Vizyonu & Felsefe

### 2.1 Misyon

Elite Agent, yapay zekânın pasif bir araç olmaktan çıkarak macOS ile doğrudan ve sürtünmesiz konuşabilen, kendi kendini denetleyen ve geliştiren **genel amaçlı otonom ajan**dır. Apple Silicon'un tüm yeteneklerini kullanan, yerleşik veri gizlilik koruması olan, gerçek bir macOS vatandaşıdır.

### 2.2 Temel Prensipler

**Antigravity**
Swift Package Manager dışında harici bağımlılık yoktur. Yalnızca Apple'ın birinci taraf framework'leri: Foundation, SwiftUI, Combine, MLX, Core ML, XPC.

**Skeleton Bass**
Actor modeli alt yapının sarsılmaz omurgasıdır. Her Actor kendi state'ini izole yönetir; üst mantık bunu asla doğrudan değiştiremez.

**Harpsichord Bridge**
MLX (local, M serisi native) ile cloud API'leri arasında maliyet, gecikme, kapasite ve veri hassasiyeti kriterlerine göre dinamik yönlendirme.

**Privacy by Architecture**
Kişisel veri koruması sonradan eklenen bir özellik değil, routing kararlarının ayrılmaz bir boyutudur. Hassas veri buluta gönderilemez; bu kural vault.plist'ten geçersiz kılınamaz.

**macOS Native Citizen**
Spotlight, Shortcuts, Share Sheet, launchd, Keychain, Notification Center — Elite Agent bu ekosistemi tam olarak kullanır. Electron veya wrapper değil, gerçek macOS uygulamasıdır.

### 2.3 OpenClaw Karşısında Konumlanma

| # | Özellik | OpenClaw | Elite Agent v5 |
|---|---------|----------|----------------|
| 1 | Platform | Linux/Windows/Mac (Electron) | macOS Only — gerçek native |
| 2 | Bağımlılık | 70+ NPM paketi | SPM + Apple 1. taraf framework |
| 3 | LLM Inference | Cloud öncelikli | MLX local öncelikli (M serisi native) |
| 4 | Paralellik | Sequential | Swift Actor paralel ajan modeli |
| 5 | Hafıza | Oturum bazlı | L1/L2 kalıcı + Git tabanlı durum |
| 6 | Maliyet | Her istek cloud | Local-first; cloud yalnızca gerektiğinde |
| 7 | UI | CLI / web | SwiftUI native pencere + Menu Bar |
| 8 | CUA | Chrome/Playwright | AXUIElement + WebKit — tüm macOS uygulamaları + Safari native |
| 9 | Güvenlik | Script-level | XPC sandbox — Apple native izolasyon |
| 10 | Veri Gizliliği | Yok | Privacy Guard — PII buluta gitmiyor |
| 11 | Xcode Entegrasyonu | Sınırlı | Xcode MCP + Swift ekosistemi native |

---

## 3. Hedef Kitle & Kullanım Senaryoları

### 3.1 Birincil Kullanıcı

- **iOS/macOS Geliştirici:** Xcode workflow otomasyonu, build/test döngüsü, kod üretimi
- **Tasarımcı + Geliştirici:** Figma → Xcode entegrasyonu, asset pipeline otomasyonu
- **Bağımsız Yazılımcı (Indie Developer):** Araştırma, dokümantasyon, çok adımlı iş akışı otomasyonu
- **Kreatif Profesyonel:** Final Cut, Logic Pro, Pages ile entegre iş akışları (Faz sonrası)

### 3.2 Görev Kategorileri

| Kategori | Örnekler | Birincil Araçlar |
|----------|----------|-----------------|
| **Araştırma** | Web araması, kaynak özetleme, karşılaştırma | `web_search`, `web_fetch`, `read_file` |
| **Dosya İşleme** | Okuma, yazma, dönüştürme, analiz | `read_file`, `write_file` |
| **Sistem Yönetimi** | Terminal komutları, süreç izleme | `shell` (XPC izolasyonu) |
| **Kod Üretimi** | Swift kodu yazma, refactor, test, debug | `write_file`, `shell`, Xcode MCP |
| **Veri İşleme** | JSON/CSV parse, filtreleme, dönüştürme | `json_parse`, `grep` |
| **Çok Adımlı İş Akışı** | Birden fazla kategorinin sıralı/paralel icrası | Tüm araçlar |
| **Uygulama Otomasyonu** | Xcode build/test, Figma tasarım, Safari/web otomasyonu | MCP Gateway + BrowserAgent |
| **Bilgisayar Kullanımı** | AXUIElement ile herhangi bir macOS uygulaması | CUA (AXUIElement) |

---

## 4. Yazılım Katman Mimarisi

Elite Agent üç katmandan oluşan tam bir macOS yazılım ürünüdür.

```
┌─────────────────────────────────────────────────────────────────┐
│                   KATMAN 1: ARAYÜZ                              │
│                                                                 │
│  ┌─────────────────┐  ┌──────────────────────────────────────┐  │
│  │  Chat Penceresi │  │         MENU BAR / STATUS ITEM        │  │
│  │    (SwiftUI)    │  │  Hızlı görev · Durum · Ayarlar        │  │
│  └────────┬────────┘  └─────────────────┬────────────────────┘  │
│           │                             │                       │
│           └──────────────┬──────────────┘                       │
│                          │  Swift Actor Message Passing         │
└──────────────────────────┼──────────────────────────────────────┘
                           │
┌──────────────────────────┼──────────────────────────────────────┐
│                   KATMAN 2: CORE (DAEMON)                       │
│                                                                 │
│  ┌────────────────────────▼───────────────────────────────────┐ │
│  │              ORCHESTRATOR (Swift Actor)                    │ │
│  │   Signal Dispatcher · Task Classifier · Monitor           │ │
│  │   Harpsichord Bridge · Privacy Routing                   │ │
│  └──┬──────────┬──────────────┬──────────────┬───────────────┘ │
│     │          │              │              │                  │
│  ┌──▼──┐  ┌────▼─────┐  ┌────▼────┐  ┌──────▼──────┐          │
│  │PLAN │  │ EXECUTOR │  │ CRITIC  │  │   MEMORY    │          │
│  │Actor│  │  Actor   │  │  Actor  │  │    Actor    │          │
│  └──┬──┘  └────┬─────┘  └────┬────┘  └──────┬──────┘          │
│     │     ┌────┴───┐         │              │                  │
│     │  ┌──▼──┐  ┌──▼──────┐  │              │                  │
│     │  │TOOL │  │   MCP   │  │              │                  │
│     │  │ ENG │  │GATEWAY  │  │              │                  │
│     │  └─────┘  └────┬────┘  │              │                  │
│     │       Xcode·Figma·Chrome│              │                  │
│     │                         │              │                  │
│  ┌──▼─────────────────────────▼──────────────▼───────────────┐ │
│  │           HARPSICHORD BRIDGE (Swift Actor)                │ │
│  │     MLX (local·M serisi) · Ollama REST · Cloud API        │ │
│  └───────────────────────────────────────────────────────────┘ │
│                                                                 │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │         GUARD ACTOR (Privacy — cloud yasak)             │   │
│  └─────────────────────────────────────────────────────────┘   │
│                                                                 │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │  AXUIElement (CUA) · Git State · L1/L2 Memory · XPC     │   │
│  └─────────────────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────────────┘
                           │
┌──────────────────────────┼──────────────────────────────────────┐
│                   KATMAN 3: KURULUM & DAEMON                    │
│                                                                 │
│  macOS Installer (.pkg)  ·  launchd plist  ·  Keychain          │
│  com.eliteagent.daemon   ·  Otomatik güncelleme                 │
└─────────────────────────────────────────────────────────────────┘
```

### 4.1 Katman 1 — Arayüz

Kullanıcının Elite Agent ile etkileşime girdiği tüm yüzeyler. Core daemon'dan bağımsız çalışır; daemon çökmüş olsa bile UI ayakta kalır.

**Chat Penceresi (SwiftUI):**
- Tam ekran veya pencere modunda çalışır
- Görev geçmişi, maliyet özeti, ajan durumu
- Markdown render desteği

**Menu Bar / Status Item:**
- Her zaman erişilebilir
- Hızlı görev başlatma (Spotlight benzeri input)
- Daemon durum göstergesi (idle / working / error)
- Maliyet özeti (bugün / bu ay)

**macOS Entegrasyonları:**
- `NSUserActivity` ile Spotlight araması
- `NSExtension` ile Share Sheet
- `INIntent` ile Siri Shortcuts
- `UNUserNotificationCenter` ile bildirimler

### 4.2 Katman 2 — Core Daemon

Elite Agent'ın kalbi. `launchd` tarafından yönetilen, sistem açılışında başlayan, arka planda sessizce çalışan süreç. Kullanıcı oturumu açmadan da çalışabilir (Heartbeat için).

Arayüz katmanıyla iletişim: **Unix Domain Socket** üzerinden Swift Concurrency mesaj geçişi.

### 4.3 Katman 3 — Kurulum & Daemon Yönetimi

Bir kez çalışan kurulum süreci. `setup.sh` değil, gerçek bir macOS installer paketi.

Kurulum adımları:
1. Uygulama bundle'ı `/Applications/EliteAgent.app` olarak kopyalanır
2. launchd plist `/Library/LaunchAgents/com.eliteagent.daemon.plist` olarak kurulur
3. Gerekli dizinler oluşturulur (`~/.eliteagent/`)
4. vault.plist şablonu oluşturulur
5. İlk çalıştırmada kullanıcıdan vault.plist doldurması istenir
6. İlk model indirmesi başlatılır (MLX veya Ollama)

---

## 5. Ajan Mimarisi — Swift Actor Modeli

### 5.1 Actor Neden?

Swift `Actor` tipi thread güvenliğini derleyici seviyesinde garanti eder:

```swift
actor PlannerAgent {
    private var state: PlannerState = .idle
    // state'e dışarıdan doğrudan erişim imkânsız
    // tüm erişim async/await üzerinden
    func receive(_ signal: Signal) async { ... }
}
```

Derleyici thread güvenliğini garanti eder. Race condition derleme zamanında yakalanır.

### 5.2 Ajan Tanımları

```swift
// Tüm ajanların uyması gereken protokol
protocol AgentProtocol: Actor {
    var agentID: AgentID { get }
    var status: AgentStatus { get }
    var preferredProvider: ProviderID { get }
    var fallbackProviders: [ProviderID] { get }

    func receive(_ signal: Signal) async throws
    func healthReport() -> AgentHealth
}

enum AgentID: String, Codable {
    case orchestrator
    case planner
    case executor
    case critic
    case memory
    case guard_ = "guard"
}

enum AgentStatus: String {
    case idle
    case working
    case waitingLLM = "waiting_llm"
    case error
}
```

### 5.3 Ajan Sorumluluk Matrisi

| Ajan | Tip | LLM (Birincil) | LLM (Yedek) | Sorumluluk |
|------|-----|----------------|-------------|------------|
| Orchestrator | `@MainActor` | — | — | UI iletişimi, sinyal dağıtımı, task classifier, monitor |
| Planner | `Actor` | MLX R1-32B | Cloud Claude / GPT-4o | Strateji, decomposition, araç + MCP seçimi |
| Executor | `Actor` | MLX Llama-3-8B | Cloud GPT-4o-mini | Tool Engine, MCP Gateway, sonuç toplama |
| Critic | `Actor` | MLX Llama-3-8B | MLX R1-8B | Kalite denetimi, self-correction tetikleme |
| Memory | `Actor` | — | — | L1/L2, retrieval, pruning, Git commit |
| Guard | `Actor` | MLX R1-8B | **Yok — cloud kesinlikle yasak** | Privacy check, desensitize, routing kararı |

> **Guard için cloud yasağı:** Guard'ın aldığı kararlar kendi başına hassas bilgidir. Bu nedenle Guard hiçbir koşulda cloud provider kullanmaz. Bu kural vault.plist'ten değiştirilemez; hardcode'dur.

### 5.4 Actor İzolasyon Kuralları

```
Kural 1: Her Actor kendi state'ini private tutar.
         Başka Actor'lar bu state'e await üzerinden mesaj göndererek erişir.

Kural 2: Memory Actor'ı L1 cache'in tek sahibidir.
         Planner, Executor, Critic doğrudan L1'e erişemez.
         MEMORY_READ / MEMORY_WRITE sinyalleri üzerinden ister.

Kural 3: Guard Actor'ı cloud provider'a erişemez.
         HarpsichordBridge.complete() çağrısında providerType == .cloud ise
         Guard'dan gelen çağrı derleme zamanında reddedilir (Swift tip sistemi).

Kural 4: Orchestrator @MainActor'dır.
         UI güncellemeleri ve kullanıcı I/O buradan yönetilir.
         Diğer Actor'lar UI'ya doğrudan erişemez.
```

### 5.5 Concurrent Görev Modeli

```swift
// Bağımsız alt görevler paralel çalışır
async let resultA = executor.run(stepA)
async let resultB = executor.run(stepB)
let (a, b) = try await (resultA, resultB)

// Maksimum eş zamanlı Executor görevi: 3
// 4. görev kuyruğa alınır
```

### 5.6 Actor Deadlock Prevention

> ⚠️ Swift Actor modeli thread-safe'dir ama deadlock-safe değildir. Bu bölüm tanımlanmamış bırakılamaz.

**Döngüsel bağımlılık yasağı:**

```
İzin verilen sinyal yönleri:
  Orchestrator → Planner, Executor, Critic, Memory, Guard
  Planner      → Orchestrator (PLAN_READY, CLARIFY_REQUEST)
  Executor     → Orchestrator (TOOL_RESULT, REVIEW_REQUEST)
  Critic       → Orchestrator (REVIEW_PASS, REVIEW_FAIL, HUMAN_ESCALATION)
  Memory       → Orchestrator (MEMORY_READ yanıtı, GIT_COMMIT)
  Guard        → Orchestrator (PRIVACY_PASS, PRIVACY_BLOCK, PRIVACY_DESENSITIZE)

KESİNLİKLE YASAK:
  Planner → Memory'ye doğrudan istek (MEMORY_READ/WRITE Orchestrator üzerinden geçer)
  Executor → Guard'a doğrudan istek (Guard kontrolü Orchestrator üzerinden)
  Memory → başka herhangi bir Actor'a sinyal (yalnızca Orchestrator'a yanıt verir)
  Guard → başka herhangi bir Actor'a sinyal (yalnızca Orchestrator'a yanıt verir)
```

**Sinyal timeout kuralı:**

```swift
// Her sinyal gönderiminde timeout zorunludur
// Timeout aşılırsa sinyal iptal edilir; ErrorSignal emit edilir
let timeoutMs: Int = switch signal.priority {
    case .critical: 10_000   // 10 sn
    case .high:     30_000   // 30 sn
    case .normal:   60_000   // 60 sn
    case .low:     120_000   // 120 sn
}

// Uygulama:
try await withThrowingTaskGroup(of: Void.self) { group in
    group.addTask {
        try await targetActor.receive(signal)
    }
    group.addTask {
        try await Task.sleep(nanoseconds: UInt64(timeoutMs) * 1_000_000)
        throw SignalError.timeout(sigID: signal.sigID, target: signal.target)
    }
    try await group.next()
    group.cancelAll()
}
```

**Timeout sonrası davranış:**

```
CRITICAL sinyal timeout → HUMAN_ESCALATION tetiklenir
HIGH / NORMAL timeout   → ErrorSignal emit; SELF_CORRECTION başlar
LOW timeout             → Görev kuyruğa alınır; 3 retry sonra iptal
```

**Deadlock tespiti (Orchestrator monitörü):**

```swift
// Orchestrator her 5 saniyede tüm Actor durumlarını kontrol eder
// Bir Actor 30 saniyeden uzun .working durumunda kalırsa:
//   → [WARN] ACTOR_STUCK audit.log'a yazılır
//   → 60 saniye sonra hâlâ working → AGENT_ISOLATION tetiklenir
```

---

## 6. LLM Inference Katmanı — Harpsichord Bridge

### 6.1 Kullanım Profilleri

Elite Agent üç farklı kullanım profilini destekler. Profil kurulum sihirbazında seçilir; vault.plist'te `routing.strategy` ile saklanır.

| Profil | routing.strategy | Local Model | Cloud | Hedef Kullanıcı |
|--------|-----------------|-------------|-------|-----------------|
| **Local-First** | `local_first` | MLX veya Ollama zorunlu | Yalnızca fallback | Yüksek RAM, gizlilik öncelikli |
| **Cloud-Only** | `cloud_only` | Gerekmez | Her zaman | Düşük RAM, yerel model kurmak istemeyen |
| **Hibrit** | `hybrid` | Küçük model (8B) yeterli | Karmaşık görevler | Orta RAM, denge arayan |

**Profil davranışları:**

```
Local-First:
  Routing: MLX → Ollama → Cloud (fallback)
  Privacy Guard: Tam aktif; PRIVACY_BLOCK → local zorunlu
  RAM: 16 GB minimum (8B model); 36 GB+ (32B model)

Cloud-Only:
  Routing: Doğrudan cloud (OpenRouter veya direkt API)
  Local model kurulumu gerekmez
  Privacy Guard: cloud_only modu (bkz. Madde 7.7)
  RAM: 8 GB yeterli (inference yapılmaz)

Hibrit:
  Routing: Küçük/hızlı görev → local 8B; Karmaşık/kritik → cloud
  Eşik: complexity >= 3 → cloud; complexity < 3 → local
  Privacy Guard: Tam aktif
  RAM: 16 GB yeterli (8B model yeterli)
```

### 6.2 Provider Hiyerarşisi

```
[Local-First]
  MLX (M serisi native)      → birincil tercih
    ↓ model mevcut değilse
  Ollama REST (Metal accel.) → ikinci tercih
    ↓ local başarısız
  Cloud API                  → son çare
    ↓ Guard PRIVACY_BLOCK varsa
    → cloud engellenir; local zorunlu

[Cloud-Only]
  Cloud API                  → doğrudan
    ↓ Guard PRIVACY_BLOCK varsa
    → görev iptal; kullanıcı uyarılır (Madde 7.7)

[Hibrit]
  complexity < 3  → Local (8B model)
  complexity >= 3 → Cloud
    ↓ Guard PRIVACY_BLOCK varsa
    → complexity ne olursa olsun local
```

### 6.3 Provider Abstraction

```swift
protocol LLMProvider: Actor {
    var providerID: ProviderID { get }
    var providerType: ProviderType { get }
    var capabilities: Set<Capability> { get }
    var costPer1KTokens: Decimal { get }    // 0 = local
    var maxContextTokens: Int { get }
    var status: ProviderStatus { get }

    func healthCheck() async -> Bool
    func complete(_ request: CompletionRequest) async throws -> CompletionResponse
}

enum ProviderType {
    case local    // MLX veya Ollama — veri makineden çıkmaz
    case cloud    // OpenAI-compat REST — Guard izni gerekir
}

enum RoutingStrategy: String, Codable {
    case localFirst  = "local_first"
    case cloudOnly   = "cloud_only"
    case hybrid      = "hybrid"
}
```

### 6.4 MLX Provider

```swift
actor MLXProvider: LLMProvider {
    private var model: LLMModel?

    func loadModel(_ modelName: String) async throws {
        self.model = try await LLMModel.load(modelName)
    }

    func complete(_ request: CompletionRequest) async throws -> CompletionResponse {
        guard let model else { throw ProviderError.modelNotLoaded }
        let output = try await model.generate(
            systemPrompt: request.systemPrompt,
            messages: request.messages,
            maxTokens: request.maxTokens,
            temperature: request.temperature ?? 0.2
        )
        return CompletionResponse(
            taskID: request.taskID,
            providerUsed: providerID,
            content: output.text,
            thinkBlock: output.thinkBlock,
            tokensUsed: output.tokenCount,
            latencyMs: output.latencyMs,
            costUSD: 0
        )
    }
}
```

### 6.5 Desteklenen Provider Listesi

| Provider ID | Tip | Protokol | Notlar |
|-------------|-----|----------|--------|
| `mlx-r1-32b` | local | MLX native | Planner; think-block; 48 GB+ Unified Memory önerilir |
| `mlx-r1-8b` | local | MLX native | Guard, Critic, Hibrit profil; 16 GB yeterli |
| `mlx-llama3-8b` | local | MLX native | Executor; 16 GB yeterli |
| `mlx-qwen25-coder` | local | MLX native | Kod görevleri; 16 GB yeterli |
| `ollama-r1-32b` | local | Ollama REST (Metal) | MLX formatı yoksa fallback |
| `ollama-llama3-8b` | local | Ollama REST (Metal) | MLX formatı yoksa fallback |
| `openrouter` | cloud | OpenRouter API (OpenAI-compat) | 200+ model; tek endpoint; bkz. Madde 6.6 |
| `claude-sonnet` | cloud | Anthropic API | Kritik görev fallback |
| `gpt-4o-mini` | cloud | OpenAI API | Düşük maliyetli cloud |
| `custom-openai-compat` | local/cloud | OpenAI-compat REST | vLLM, Groq, Mistral vb. |

### 6.6 OpenRouter Provider

OpenRouter, tek bir API endpoint üzerinden 200+ modele erişim sağlar. `custom-openai-compat` tipi ile implement edilir; ek kod gerekmez.

**Model path formatı:** OpenRouter'da model adı `provider/model-name` formatındadır:

```
deepseek/deepseek-r1          → R1 (think-block destekler)
meta-llama/llama-3.1-8b-instruct
anthropic/claude-sonnet-4-5
google/gemini-2.0-flash
mistralai/mistral-7b-instruct
```

**vault.plist OpenRouter tanımı:**

```xml
<dict>
  <key>id</key><string>openrouter-r1</string>
  <key>type</key><string>openrouter</string>
  <key>endpoint</key><string>https://openrouter.ai/api/v1</string>
  <key>keychainKey</key><string>com.eliteagent.api.openrouter</string>
  <key>modelName</key><string>deepseek/deepseek-r1</string>
  <key>capabilities</key>
  <array><string>think</string><string>code</string><string>general</string></array>
  <key>costPer1KTokens</key><real>0.0008</real>
  <key>maxContextTokens</key><integer>65536</integer>
</dict>
```

**Capabilities belirleme kuralı:**

OpenRouter model listesi otomatik sorgulanmaz. Kullanıcı vault.plist'te `capabilities` alanını manuel tanımlar. Kural:

```
"think" capability → yalnızca R1, o1/o3 serisi modeller için ekle
                     Diğer modellere eklenirse think_block parse atlanır;
                     think=false gibi davranılır
"fast"             → 7B ve altı modeller için uygun
"long_context"     → 64K+ context window için
```

**OpenRouter özel header'ları:**

```swift
// URLSession isteğine ek header'lar eklenir
request.setValue("https://eliteagent.app", forHTTPHeaderField: "HTTP-Referer")
request.setValue("EliteAgent/5.1", forHTTPHeaderField: "X-Title")
```

### 6.7 Routing Karar Matrisi

```
[Tüm profiller için ortak ön kontrol]
1. Guard Privacy kararı var mı?
   PRIVACY_BLOCK + cloud_only profil → Madde 7.7 davranışı
   PRIVACY_BLOCK + local_first/hybrid → providerType = .local zorunlu

[Local-First]
2. Dynamic Downscaling aktif mi? (Madde 6.8)
   EVET → indirilmiş model kullan
3. MLX hazır ve yeterli RAM var mı?
   EVET → MLX kullan
4. Ollama hazır mı?
   EVET → Ollama kullan
5. → cloud fallback (vault.agents[ajan].fallback)

[Cloud-Only]
2. → Doğrudan cloud provider kullan

[Hibrit]
2. complexity < 3 → local (8B model) adımlarına git
   complexity >= 3 → cloud fallback adımlarına git
3. Dynamic Downscaling aktif mi? → indirilmiş model
4. MLX/Ollama 8B hazır mı? → local kullan
5. → cloud provider

[Tüm profiller için son adım]
X. Tüm providerlar başarısız → kuyruğa al; retry_policy uygula
```

### 6.8 Dynamic Downscaling — Performans Modu

> Bu madde R1-32B modelinin yüksek RAM tüketimi (gerçek deneyim: ~120 GB) ve kullanıcı makinesi donması sorununa yanıt verir.

**Tetikleyici koşullar:**

```swift
struct PerformanceMonitor {
    // Her 10 saniyede bir ölçüm alınır
    func checkPressure() -> MemoryPressure {
        // macOS memory pressure API
        // vm_stat ve host_statistics64 üzerinden
    }
}

enum MemoryPressure {
    case normal    // Downscaling gerekmez
    case elevated  // Uyarı; küçük modele geçişi hazırla
    case critical  // Anında küçük modele geç + inference'ı yavaşlat
}
```

**Downscaling kararı:**

```
memory pressure = .elevated:
  → Planner: mlx-r1-32b → mlx-r1-8b
  → audit.log: [PERF] DOWNSCALE r1-32b → r1-8b (pressure=elevated)
  → UI'da sarı gösterge: "Performans modu aktif"

memory pressure = .critical:
  → Tüm local modeller → en küçük mevcut model
  → Yeni inference başlatılmaz; mevcut tamamlanır
  → cloud_only/hybrid profilde → doğrudan cloud
  → UI'da turuncu gösterge + bildirim: "Bellek baskısı yüksek"

memory pressure = .normal'a dönünce:
  → 60 sn beklenir (spike değilse)
  → Orijinal model seçimine geri dönülür
  → UI göstergesi temizlenir
```

**Pause on User Interaction:**

```
Kullanıcı fare/klavye aktivitesi tespit edilirse (NSEvent.addGlobalMonitorForEvents):
  → Devam eden inference tamamlanır (kesilemez)
  → Yeni inference isteği kuyruğa alınır
  → Kullanıcı aktivitesi 3 sn durunca → kuyruk devam eder
  → vault.plist: inference.pauseOnUserInteraction = true/false (varsayılan: true)
```

### 6.9 Donanım Bazlı Model Öneri Tablosu

> ⚠️ Bu tablo deneyimsel değerlere dayanır. R1-32B'nin gerçek RAM tüketimi ~120 GB olarak gözlemlenmiştir; sadece model boyutuna göre hesaplama yanıltıcıdır.

| Chip | Unified Memory | Önerilen Profil | Planner | Executor/Critic | Guard |
|------|---------------|-----------------|---------|-----------------|-------|
| M1 / M2 | 8 GB | Cloud-Only | cloud | cloud | mlx-r1-8b (dikkatli) |
| M1 / M2 | 16 GB | Hibrit | cloud | mlx-llama3-8b | mlx-r1-8b |
| M1 Pro/Max | 32 GB | Hibrit | cloud veya mlx-r1-8b | mlx-llama3-8b | mlx-r1-8b |
| M2 Pro/Max | 32–96 GB | Local-First | mlx-r1-8b (32GB) / mlx-r1-32b (96GB+) | mlx-llama3-8b | mlx-r1-8b |
| M3 Pro/Max | 36–128 GB | Local-First | mlx-r1-8b (36GB) / mlx-r1-32b (128GB) | mlx-llama3-8b | mlx-r1-8b |
| M4 Pro/Max | 24–128 GB | Local-First | mlx-r1-8b (24GB) / mlx-r1-32b (128GB) | mlx-llama3-8b | mlx-r1-8b |
| M3/M4 Ultra | 192–512 GB | Local-First | mlx-r1-32b | mlx-llama3-8b | mlx-r1-8b |

**Notlar:**
- R1-32B için 96 GB+ Unified Memory önerilebilir minimum. 64 GB'ta swap devreye girebilir.
- 8 GB makinede local model çalıştırmak önerilmez; Cloud-Only profil seçilmeli.
- Kurulum sihirbazı cihazın RAM'ini otomatik okuyup bu tablodan profil önerisi yapar.

```swift
// Kurulum sihirbazında otomatik profil önerisi
func suggestProfile() -> RoutingStrategy {
    let ram = ProcessInfo.processInfo.physicalMemory / (1024 * 1024 * 1024) // GB
    switch ram {
    case ..<16:  return .cloudOnly
    case 16..<32: return .hybrid
    default:     return .localFirst
    }
}
```

### 6.10 Sensitivity Routing

```swift
enum SensitivityLevel: String, Codable {
    case `public`       // cloud serbest
    case `internal`     // cloud serbest; desensitize tavsiye edilir
    case confidential   // yalnızca local; cloud bloğu
}
```

`confidential` sınıflandırmasında Harpsichord Bridge cloud provider'ı devre dışı bırakır. Cloud-Only profilde bu `confidential` görev iptaline yol açar (bkz. Madde 7.7).

### 6.11 CompletionRequest & CompletionResponse

```swift
struct CompletionRequest: Codable {
    let taskID: String
    let systemPrompt: String
    let messages: [Message]
    let maxTokens: Int
    var temperature: Double?     // varsayılan: 0.2
    var requiredCapabilities: [Capability]?
    var maxLatencyMs: Int?       // varsayılan: 30_000
    var sensitivityLevel: SensitivityLevel
    var complexity: Int          // 1-5; Hibrit profil routing için
}

struct CompletionResponse: Codable {
    let taskID: String
    let providerUsed: ProviderID
    let content: String
    let thinkBlock: String?
    let tokensUsed: TokenCount
    let latencyMs: Int
    let costUSD: Decimal
    var error: ProviderError?
}
```

---

## 7. Privacy Guard — Veri Gizlilik Katmanı

### 7.1 Mimari Konum

Guard Actor, her cloud'a gidecek içeriği üç karardan birine yönlendirir:

```
S1 — PRIVACY_PASS:        Hassas veri yok → cloud routing serbest
S2 — PRIVACY_DESENSITIZE: Hassas veri var ama maskelenebilir → maskele → cloud serbest
S3 — PRIVACY_BLOCK:       Hassas veri var ve maskelenemiyor → yalnızca local
```

### 7.2 Action Guard

```swift
actor GuardAgent: AgentProtocol {
    private let ruleChecker: RuleBasedChecker    // regex; < 10 ms
    private let modelChecker: LocalModelChecker  // MLX R1-8B; < 3000 ms

    func checkPrivacy(_ payload: String) async -> PrivacyDecision {
        // 1. Rule-based (önce çalışır)
        if let ruleDecision = ruleChecker.check(payload) {
            return ruleDecision   // BLOCK veya DESENSITIZE
        }
        // 2. Model-based (rule geçerse)
        return await modelChecker.check(payload)
    }
}
```

**Rule-based:** vault.plist'teki regex pattern listesi; LLM çağrısı olmaz; < 10 ms.

**Model-based:** MLX R1-8B ile PII tespiti; timeout 3000 ms; timeout aşılırsa PRIVACY_PASS varsayılır ve audit.log'a `[WARN]` yazılır.

### 7.3 Desensitize Protokolü

```
PRIVACY_DESENSITIZE kararında Guard şu adımları uygular:

1. block_patterns → tam silme ([REDACTED])
2. desensitize_patterns → kısmi maskeleme:
   TC Kimlik  → [TC_KIMLIK]
   İsim       → [KİŞİ]
   Telefon    → [TELEFON]
   IBAN       → [IBAN]
   E-posta    → [EPOSTA]
   Koordinat  → [KONUM]
3. Maskelenmiş içerik cloud'a gönderilir
4. Ham içerik yalnızca KNOWLEDGE_BASE-FULL.md'de saklanır
5. security.log: [ISO] [GUARD] DESENSITIZE categories=[isim,telefon]
```

### 7.4 Memory Guard — İkili Bellek

```
KNOWLEDGE_BASE-FULL.md  → Yalnızca local LLM erişir; PII dahil
KNOWLEDGE_BASE.md       → Cloud-safe; PII çıkarılmış / maskelenmiş
```

Senkronizasyon akışı Swift Actor sinyalleriyle çalışır.

### 7.5 Guard Performans Kısıtları

```
Rule-based check     : < 10 ms
Model-based check    : < 3000 ms (timeout → PRIVACY_PASS + [WARN] log)
Guard toplam latency : < 3000 ms kritik yol; aşılırsa PRIVACY_PASS varsayılır
```

### 7.6 Privacy Guard Cache

> Bu madde olmadan 50 araç çağrısı olan bir görevde Guard latency toplamı dakikaları bulur.

**Cache mantığı:**

```swift
actor GuardAgent: AgentProtocol {
    // Payload hash → karar önbelleği
    // TTL: 300 saniye (5 dakika); sonra yeniden kontrol
    private var decisionCache: [String: CachedDecision] = [:]

    struct CachedDecision {
        let decision: PrivacyDecision
        let timestamp: Date
        let ttl: TimeInterval = 300
        var isExpired: Bool { Date().timeIntervalSince(timestamp) > ttl }
    }

    func checkPrivacy(_ payload: String) async -> PrivacyDecision {
        let hash = SHA256.hash(data: Data(payload.utf8))
            .compactMap { String(format: "%02x", $0) }.joined()

        // Cache hit
        if let cached = decisionCache[hash], !cached.isExpired {
            await AuditLog.write("[GUARD] CACHE_HIT hash=\(hash.prefix(8))")
            return cached.decision
        }

        // Cache miss → normal kontrol
        let decision = await runChecks(payload)
        decisionCache[hash] = CachedDecision(decision: decision, timestamp: Date())
        return decision
    }
}
```

**Cache kuralları:**

```
Cache anahtarı    : SHA-256(payload) — içerik değişince yeni kontrol
TTL               : 300 sn (vault.plist'te privacy.cacheTTLSeconds ile değiştirilebilir)
Cache boyutu      : Maksimum 500 entry; FIFO ile temizlenir
PRIVACY_BLOCK     : Cache'lenir (aynı içerik tekrar gönderilmeye çalışılırsa hemen red)
PRIVACY_PASS      : Cache'lenir
PRIVACY_DESENSITIZE: Cache'lenmez; maskeleme her seferinde taze yapılır

Cache temizleme   : Oturum kapandığında; manuel vault.plist değişikliğinde
```

### 7.7 Cloud-Only Profilde Privacy Guard Davranışı

Cloud-Only profilde local LLM yoktur. `PRIVACY_BLOCK` kararı alındığında "local'e yönlendir" seçeneği mevcut değildir.

```
PRIVACY_BLOCK + cloud_only profil:

  1. Görev durdurulur
  2. SwiftUI'da modal uyarı gösterilir:

     ╔══════════════════════════════════════════════════╗
     ║  GİZLİLİK UYARISI                               ║
     ║  Bu görev hassas veri içeriyor (kategori: {X}).  ║
     ║  Cloud-Only modda bu veri işlenemiyor.           ║
     ║                                                  ║
     ║  Seçenekler:                                     ║
     ║  [Görevi İptal Et]                               ║
     ║  [Hassas Veriyi Çıkararak Devam Et]              ║
     ║  [Hibrit Moda Geç — Local Model Kur]             ║
     ╚══════════════════════════════════════════════════╝

  3a. Görevi İptal Et → görev CANCELLED; audit.log'a yazılır
  3b. Hassas Veriyi Çıkararak Devam Et → Guard desensitize uygular;
      maskelenmiş içerikle cloud'a gönderilir
  3c. Hibrit Moda Geç → kurulum sihirbazı açılır; local model indirilir;
      tamamlanınca görev yeniden denenir

PRIVACY_BLOCK + cloud_only + otomatik mod (vault.plist: privacy.cloudOnlyBlockBehavior):
  "cancel"      → sessizce iptal (bildirim + log)
  "desensitize" → otomatik maskele ve devam et (varsayılan)
  "warn"        → modal göster (yukarıdaki akış)
```

---

## 8. Teknik Stack — Swift Native-First

### 8.1 Onaylı Stack

| Katman | Teknoloji | Notlar |
|--------|-----------|--------|
| Dil | Swift 6 | Strict concurrency; tüm Actor modeli |
| UI | SwiftUI + AppKit | Chat penceresi + Menu Bar NSStatusItem |
| Concurrency | Swift Actors + async/await | Worker Thread ve SharedArrayBuffer yok |
| LLM (Local) | MLX Swift + Ollama REST | MLX öncelikli; M serisi native |
| LLM (Cloud) | URLSession + OpenAI-compat | Tüm cloud'lar aynı adaptor |
| Networking | URLSession (Foundation) | Harici HTTP kütüphanesi yasak |
| Sandbox | XPC Services | child_process.spawn yok; Apple native |
| CUA | AXUIElement + WebKit | BrowserAgent — Safari native; harici npm paketi yok |
| Daemon | launchd | setup.sh yok; sistem servisi |
| Storage | FileManager + PropertyList | SQLite ve ORM yasak |
| Secrets | Keychain + vault.plist | API key'ler Keychain'de |
| Paket Yönetimi | Swift Package Manager | npm/yarn yok |
| Build | Xcode | Tek build ortamı |

### 8.2 Kesinlikle Yasak

| Yasak | Alternatif |
|-------|-----------|
| Electron, React Native | SwiftUI native |
| Herhangi bir npm paketi | Swift Package Manager |
| Python runtime | Foundation + MLX |
| LangChain, LlamaIndex | Doğrudan MLX / URLSession |
| ORMLite, SQLite | FileManager + PropertyList + JSONL |
| Alamofire, Moya | URLSession native |
| RxSwift | Swift Concurrency + Combine |
| Harici PII kütüphanesi | Regex + Local MLX model |
| Docker | XPC Services |

### 8.3 Swift Package Bağımlılıkları

```swift
// Package.swift
dependencies: [
    // MLX inference — Apple'ın resmi M serisi ML framework'ü
    .package(url: "https://github.com/ml-explore/mlx-swift", from: "0.10.0"),
    // MLX LLM yardımcı katmanı
    .package(url: "https://github.com/ml-explore/mlx-swift-examples", from: "1.0.0"),
]
```

> Bu iki paket dışında harici bağımlılık eklenemez. Yeni bağımlılık eklenmeden önce bu doküman güncellenir.

---

## 9. Sinyal Sözleşmeleri

### 9.1 Signal Yapısı

```swift
struct Signal: Codable, Sendable {
    let sigID: UUID
    let priority: Priority
    let origin: AgentID
    let target: AgentID
    let ttlMs: Int
    let retryPolicy: RetryPolicy
    let payload: SignalPayload
    let hmacSignature: String   // HMAC-SHA256

    enum Priority: String, Codable {
        case critical, high, normal, low
    }

    struct RetryPolicy: Codable {
        let maxRetries: Int
        let delayMs: Int
    }
}
```

### 9.2 Sinyal Tablosu

| Sinyal | Gönderen | Alan | Anlamı |
|--------|---------|------|--------|
| `TASK_START` | Orchestrator | Planner | Yeni görev |
| `PLAN_READY` | Planner | Orchestrator | Plan hazır |
| `PRIVACY_CHECK` | Orchestrator / Memory | Guard | Payload hassasiyet kontrolü |
| `PRIVACY_PASS` | Guard | Orchestrator | Cloud routing serbest |
| `PRIVACY_BLOCK` | Guard | Orchestrator | Cloud routing yasak |
| `PRIVACY_DESENSITIZE` | Guard | Orchestrator | Maskelenmiş payload ile devam |
| `TOOL_CALL` | Executor | Tool Engine | Araç çağrısı |
| `TOOL_RESULT` | Tool Engine | Executor | Araç sonucu |
| `MCP_CALL` | Executor | MCP Gateway | MCP sunucu çağrısı |
| `MCP_RESULT` | MCP Gateway | Executor | MCP yanıtı |
| `MCP_SERVER_DOWN` | MCP Gateway | Orchestrator | MCP sunucu yanıt vermiyor |
| `CUA_ACTION` | Executor | CUA | AXUIElement aksiyonu |
| `CUA_RESULT` | CUA | Executor | Aksiyon sonucu |
| `BROWSER_ACTION` | Executor | BrowserAgent | Safari navigasyon / JS / form aksiyonu |
| `BROWSER_RESULT` | BrowserAgent | Executor | Aksiyon sonucu + sayfa durumu |
| `BROWSER_ERROR` | BrowserAgent | Orchestrator | Domain yasak / izin yok / timeout |
| `GIT_COMMIT` | Memory | Git State Engine | Otomatik commit |
| `GIT_REVERT` | Orchestrator | Git State Engine | Kullanıcı onaylı geri alma |
| `REVIEW_REQUEST` | Executor | Critic | Sonuç denetimi |
| `REVIEW_PASS` | Critic | Orchestrator | Onaylandı |
| `REVIEW_FAIL` | Critic | Orchestrator | Hata; self-correction |
| `MEMORY_WRITE` | Herhangi | Memory | L1/L2 yazma |
| `MEMORY_READ` | Herhangi | Memory | L2 retrieval |
| `CLARIFY_REQUEST` | Planner | Orchestrator | Kullanıcıdan açıklama |
| `USER_INPUT` | Orchestrator | Planner | Kullanıcı yanıtı |
| `TASK_COMPLETE` | Orchestrator | — | Görev tamamlandı |
| `HUMAN_ESCALATION` | Critic | Orchestrator | İnsan müdahalesi gerek |
| `SECURITY_FLAG` | Herhangi | Orchestrator | Güvenlik ihlali |
| `AGENT_ISOLATION` | Orchestrator | — | Ajan devre dışı |

### 9.3 HMAC İmzalama

Secret Keychain'de saklanır; Actor'lar aynı process içinde çalıştığından şu şekilde erişilir:

```swift
// Secret Keychain'den okunur; bellekte tutulur
// Her signal oluşturulurken imzalanır
struct SignalSigner {
    private let secret: SymmetricKey   // CryptoKit

    func sign(_ signal: inout Signal) {
        let data = try! JSONEncoder().encode(signal.payload)
        let mac = HMAC<SHA256>.authenticationCode(for: data, using: secret)
        signal.hmacSignature = Data(mac).base64EncodedString()
    }

    func verify(_ signal: Signal) -> Bool {
        let data = try! JSONEncoder().encode(signal.payload)
        let mac = HMAC<SHA256>.authenticationCode(for: data, using: secret)
        let expected = Data(mac).base64EncodedString()
        return signal.hmacSignature == expected
    }
}
```

Secret, Keychain'de `com.eliteagent.hmac_secret` anahtarıyla saklanır. vault.plist'te düz metin olarak tutulmaz.

---

## 10. Tool Engine — Araç Sistemi

### 10.1 Tool Tanım Sözleşmesi

```swift
struct ToolDefinition: Codable {
    let toolID: String
    let description: String      // LLM'e sunulan açıklama
    let category: ToolCategory
    let requiresSandbox: Bool    // true → XPC Service üzerinden
    let requiresApproval: Bool
    let requiresPrivacyCheck: Bool
    let params: [String: ParamDefinition]
    let handlerClass: String     // Swift class adı

    enum ToolCategory: String, Codable {
        case filesystem, system, network, data, mcp, cua
    }
}
```

### 10.2 Araç Listesi

| Tool ID | Kategori | Sandbox | Onay | Privacy | Açıklama |
|---------|----------|---------|------|---------|----------|
| `read_file` | filesystem | hayır | hayır | evet | Dosya okuma |
| `write_file` | filesystem | hayır | **evet** | evet | Dosya yazma (atomic) |
| `list_dir` | filesystem | hayır | hayır | hayır | Dizin listeleme |
| `delete_file` | filesystem | **evet** | **evet** | hayır | Dosya silme (XPC) |
| `shell` | system | **evet (XPC)** | **evet** | evet | Terminal komutu (XPC izolasyonu) |
| `web_search` | network | hayır | hayır | evet | DuckDuckGo arama |
| `web_fetch` | network | hayır | hayır | evet | URL içeriği |
| `json_parse` | data | hayır | hayır | hayır | JSON parse + path query |
| `grep` | data | hayır | hayır | hayır | Regex arama |
| `summarize` | data | hayır | hayır | evet | LLM özetleme |
| `desensitize` | data | hayır | hayır | — | Yalnızca Guard kullanabilir |
| `mcp_call` | mcp | hayır | bağlama göre | evet | MCP Gateway |
| `cua_action` | cua | hayır | tip'e göre | evet | AXUIElement |

### 10.3 XPC Sandbox (shell aracı)

Shell komutları XPC Service izolasyonunda çalışır.

```swift
// SandboxXPCService — ayrı process, kısıtlı entitlement
// Entitlements:
//   com.apple.security.temporary-exception.files.absolute-path.read-write: /tmp/eliteagent/
//   com.apple.security.temporary-exception.files.absolute-path.read-write: ~/Documents/

class SandboxXPCService: NSObject, NSXPCListenerDelegate, SandboxProtocol {
    func execute(command: String, workingDir: String) async throws -> CommandResult {
        // Yasak pattern kontrolü
        guard !ForbiddenPatterns.matches(command) else {
            throw SandboxError.forbiddenCommand(command)
        }
        // XPC izolasyonunda çalıştır
        return try await runInIsolation(command: command, cwd: workingDir)
    }
}
```

---

## 11. MCP Gateway

### 11.1 Transport

```swift
enum MCPTransport {
    case stdio(command: String)           // child process (XPC üzerinden)
    case sse(url: URL, apiKey: String?)   // Server-Sent Events
}
```

### 11.2 Desteklenen Sunucular

| server_id | Transport | Örnek Araçlar |
|-----------|-----------|---------------|
| `xcode-mcp` | stdio | `build_project`, `run_tests`, `get_build_errors`, `open_simulator` |
| `figma-mcp` | sse | `get_file`, `get_component`, `export_asset`, `list_pages` |
| `custom-mcp` | stdio/sse | vault.plist'ten dinamik |

> **Not:** `chrome-mcp` bu versiyonda kaldırılmıştır. Tarayıcı otomasyonu artık native Swift `BrowserAgent` ile yapılır (bkz. Madde 13.6). Harici npm paketi gerekmez.

### 11.3 MCP Güvenlik

- Yalnızca vault.plist'te tanımlı sunuculara bağlantı
- `xcode-mcp`: `xcode_allowed_schemes` listesi zorunlu
- Tüm MCP çağrıları Guard Privacy Check'ten geçer
- 3 ardışık timeout → sunucu `offline` işaretlenir

---

## 12. Git State Engine

```swift
actor GitStateEngine {
    private let projectRoot: URL

    func commit(message: String) async {
        do {
            try await run("git", args: ["add", "-A"])
            try await run("git", args: ["commit", "-m", message, "--allow-empty"])
        } catch {
            // Git hatası ajanı durdurmamalı
            await AuditLog.write("[GIT_ERROR] \(error.localizedDescription)")
        }
    }

    private func run(_ executable: String, args: [String]) async throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/\(executable)")
        process.arguments = args
        process.currentDirectoryURL = projectRoot
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            throw GitError.nonZeroExit(process.terminationStatus)
        }
    }
}
```

### 12.1 Commit Tetikleyiciler

| Olay | Commit Mesajı |
|------|---------------|
| Görev tamamlandı | `agent: task complete — {taskID}` |
| Dosya yazıldı | `agent: write {filename} — {taskID}` |
| Dosya silindi | `agent: delete {filename} — {taskID}` |
| KNOWLEDGE_BASE güncellendi | `agent: knowledge update — {summary}` |
| Self-correction | `agent: self-correct retry#{n} — {taskID}` |
| MCP işlemi | `agent: mcp {serverID}/{tool} — {taskID}` |
| Privacy sync | `agent: privacy sync — full+safe updated` |

---

## 13. CUA & BrowserAgent — AXUIElement + WebKit

Elite Agent'ın en güçlü farklılaştırıcısı iki katmandan oluşur:

**AXUIElement (CUA):** Tüm macOS uygulamalarını kontrol eder — Xcode, Finder, Mail, Slack, Figma desktop dahil.

**BrowserAgent (WebKit):** Safari'yi native olarak kontrol eder. JavaScript inject, DOM okuma, form doldurma, sayfa navigasyonu. Harici npm paketi yok, debug protokolü yok — tamamen Swift native.

```
AXUIElement  →  tüm macOS uygulamaları (genel CUA)
BrowserAgent →  Safari + web uygulamaları (derin tarayıcı kontrolü)
```

### 13.1 Mimari Üstünlük

```
AXUIElement:   Tüm macOS uygulamaları → Accessibility tree
               Xcode, Finder, Mail, Slack, Figma desktop, Safari, her şey

BrowserAgent:  Safari → WebKit native
               JavaScript inject, DOM sorgusu, form doldurma,
               sayfa yükleme, network intercept
               chrome-mcp veya herhangi bir npm paketine gerek yok
```

### 13.2 CUA Karar Döngüsü

```swift
actor CUALayer {
    func execute(goal: String) async throws -> CUAResult {
        var stepCount = 0
        let maxSteps = vault.cua.maxSteps  // varsayılan: 20

        while stepCount < maxSteps {
            // 1. OBSERVE
            let state = try await observe()   // accessibility tree öncelikli

            // 2. DECIDE
            let action = try await planner.decide(goal: goal, state: state)

            // 3. ACT
            if action.requiresApproval {
                try await requestUserApproval(action)
            }
            try await perform(action)

            // 4. VERIFY
            if try await isGoalComplete(goal: goal) { break }
            stepCount += 1
        }

        if stepCount >= maxSteps {
            throw CUAError.maxStepsExceeded  // → HUMAN_ESCALATION
        }
    }
}
```

### 13.3 AXUIElement Wrapper

```swift
struct AccessibilityBridge {
    // Screenshot yerine accessibility tree öncelikli
    func getAccessibilityTree(for app: NSRunningApplication) throws -> AXTree {
        let axApp = AXUIElementCreateApplication(app.processIdentifier)
        return try AXTree(root: axApp)
    }

    // Tüm macOS uygulamaları hedeflenebilir
    func click(element: AXElement) throws {
        try AXUIElementPerformAction(element.ref, kAXPressAction as CFString)
    }

    func type(text: String, into element: AXElement) throws {
        // Her zaman kullanıcı onayı gerekir (sinyal tablosu)
        AXUIElementSetAttributeValue(element.ref,
            kAXValueAttribute as CFString, text as CFTypeRef)
    }
}
```

### 13.4 Screenshot Kuralı

```
Kural 1: Accessibility tree her zaman screenshot'a tercih edilir.
Kural 2: Screenshot yalnızca tree'nin yetersiz kaldığı durumda kullanılır
         (canvas, oyun, özel render motoru).
Kural 3: Screenshot maksimum 1280×720, JPEG quality 70.
Kural 4: screenshot_b64 audit.log'a yazılmaz; yalnızca boyut notu düşülür.
Kural 5: Screenshot Guard Privacy Check'ten geçer (ekranda PII olabilir).
```

### 13.5 AXUIElement Kırılganlık Yönetimi

> ⚠️ AXUIElement pratik bir kabustur. Uygulama güncellemelerinde element identifier'ları değişir; "hayalet" elementler oluşabilir. Bu riskler tanımlanmamış bırakılamaz.

**Sorun 1: Identifier değişimi**

Xcode 16.2 → 16.3 gibi güncellemelerde `AXIdentifier` değerleri değişebilir. Ajan "eleman bulunamadı" döngüsüne girer.

```
Çözüm — Çoklu tanımlayıcı stratejisi:
  1. AXIdentifier ile ara (birincil)
  2. Bulunamazsa → AXTitle + AXRole kombinasyonu ile ara
  3. Bulunamazsa → AXDescription ile ara
  4. Hiçbiri bulunamazsa → CLARIFY_REQUEST:
     "Hedef element bulunamadı. Lütfen ekrandaki hedefi tanımlayın."
  5. max_steps sayacı artırılır (element arama adımı sayılır)
```

**Sorun 2: Hayalet elementler**

Özellikle Finder ve Safari bazen tree'de görünüp tıklanamayan "hayalet" elementler üretir.

```
Çözüm — Aksiyon doğrulama:
  Her tıklama / yazma aksiyonundan sonra:
  1. 500 ms bekle
  2. Tree'yi yeniden oku
  3. Beklenen değişiklik gerçekleşti mi? (örn: dialog kapandı mı?)
     EVET → başarılı; devam et
     HAYIR → aksiyonu tekrar dene (max 2 kez)
     2 denemede de başarısız → screenshot al; Guard'dan geç; LLM'e gönder
     "Bu ekran durumunda ne yapmalıyım?" sorgusu
```

**Sorun 3: Erişilebilirlik izni**

macOS Sistem Ayarları → Gizlilik → Erişilebilirlik'te Elite Agent'a izin verilmemiş olabilir.

```
Bootstrap sırasında kontrol:
  AXIsProcessTrustedWithOptions() → false ise:
  → SwiftUI modal: "CUA özelliği için Erişilebilirlik izni gerekiyor"
  → [Sistem Ayarlarını Aç] butonu
  → İzin verilene kadar CUA disabled olarak işaretlenir
  → vault.cua.enabled otomatik false kalır
```

**Genel kırılganlık azaltma kuralları:**

```
1. CUA adımı başarısız olursa önce retry (max 2), sonra SELF_CORRECTION
2. max_steps aşılırsa HUMAN_ESCALATION — sonsuz döngü koruması
3. Her CUA oturumu başında uygulamanın çalışıp çalışmadığı kontrol edilir
4. Uygulama kapanırsa CUA_SESSION_INTERRUPTED sinyali emit edilir
```

### 13.6 BrowserAgent — Safari Native

> Safari, macOS'un yerleşik tarayıcısıdır. Hem AXUIElement hem de WebKit framework üzerinden iki ayrı katmanda kontrol edilir. `chrome-mcp` gibi harici bir bağımlılığa gerek yoktur.

**İki katman — ne zaman hangisi:**

```
AXUIElement katmanı (her zaman mevcut):
  → Toolbar, adres çubuğu, sekme listesi, butonlar
  → Sayfa içi erişilebilirlik elementleri (linkler, butonlar, form alanları)
  → Hızlı; JavaScript gerektirmez

WebKit katmanı (daha derin erişim):
  → JavaScript inject ve çalıştırma
  → DOM sorgusu (querySelector benzeri)
  → Sayfa HTML/metin içeriği okuma
  → Form doldurma ve gönderme
  → Sayfa yükleme durumu takibi
```

**Swift implementasyonu:**

```swift
actor BrowserAgent {
    // Katman 1: AXUIElement — Safari penceresi ve tab kontrolü
    private let axBridge: AccessibilityBridge

    // Katman 2: WKWebView köprüsü — JavaScript ve DOM erişimi
    // Not: Doğrudan WKWebView kullanmak yerine Safari'nin
    // mevcut penceresine AppleScript köprüsü üzerinden
    // JavaScript inject edilir (sandboxed)
    private let jsBridge: SafariJSBridge

    func navigate(to url: URL) async throws {
        // AXUIElement ile adres çubuğunu bul ve URL yaz
        let urlField = try axBridge.findElement(
            in: "com.apple.Safari",
            role: kAXTextFieldRole,
            identifier: "WEB_BROWSER_ADDRESS_AND_SEARCH_FIELD"
        )
        try axBridge.setValue(url.absoluteString, for: urlField)
        try axBridge.pressReturn(on: urlField)
        // Sayfa yüklenene kadar bekle
        try await waitForPageLoad()
    }

    func readPageText() async throws -> String {
        // JavaScript ile sayfa metnini al
        return try await jsBridge.evaluate(
            "document.body.innerText"
        )
    }

    func querySelector(_ selector: String) async throws -> [DOMElement] {
        let script = """
        JSON.stringify([...document.querySelectorAll('\(selector)')].map(el => ({
            tag: el.tagName,
            text: el.innerText,
            href: el.href || null,
            id: el.id || null
        })))
        """
        let json = try await jsBridge.evaluate(script)
        return try JSONDecoder().decode([DOMElement].self,
                                        from: Data(json.utf8))
    }

    func fillForm(fields: [String: String]) async throws {
        // Her alan için: querySelector ile bul → AXUIElement ile doldur
        // JavaScript yerine AXUIElement tercih edilir (daha güvenilir)
        for (selector, value) in fields {
            let elements = try await querySelector(selector)
            guard let first = elements.first else { continue }
            // AXUIElement ile değer set et
            try await axBridge.setValueByCoordinates(first.rect, value: value)
        }
    }
}
```

**SafariJSBridge — JavaScript inject mekanizması:**

```swift
// AppleScript üzerinden Safari'ye JavaScript gönderilir
// Bu macOS'un native IPC mekanizmasıdır; harici araç gerektirmez
struct SafariJSBridge {
    func evaluate(_ script: String) async throws -> String {
        let appleScript = """
        tell application "Safari"
            tell current tab of front window
                do JavaScript "\(script.escapedForAppleScript())"
            end tell
        end tell
        """
        return try await NSAppleScript(source: appleScript)!
            .executeAndReturnError(nil).stringValue ?? ""
    }
}
```

**BrowserAgent yetenek tablosu:**

| Yetenek | AXUIElement | JavaScript (SafariJSBridge) |
|---------|-------------|----------------------------|
| URL'ye git | ✅ | ✅ |
| Sayfa başlığı/URL oku | ✅ | ✅ |
| Butona tıkla | ✅ | ✅ |
| Form doldur | ✅ | ✅ |
| Sayfa tam metnini oku | ✅ (kısıtlı) | ✅ (tam) |
| DOM sorgusu (CSS selector) | ❌ | ✅ |
| JavaScript çalıştır | ❌ | ✅ |
| Sayfa yükleme durumu | ✅ | ✅ |
| Screenshot | ✅ (ekran) | ❌ |
| Sekme yönetimi | ✅ | ✅ |
| Yeni sekme/pencere | ✅ | ✅ |

**BrowserAgent güvenlik kuralları:**

```
1. Yalnızca vault.plist'teki browser.allowedDomains listesindeki
   domain'lere navigate edilebilir.

2. JavaScript inject her zaman kullanıcı onayı gerektirir
   (executeJS → requires_approval = true; değiştirilemez).

3. Form doldurma (fillForm) requires_approval = true.
   Otomatik form gönderimi (submit) ayrıca onay gerektirir.

4. Tüm BrowserAgent aksiyonları audit.log'a yazılır:
   [ISO] [BROWSER] action={navigate|read|query|fill} url={domain} status={result}

5. Sayfa içeriği Guard Privacy Check'ten geçer
   (sayfada PII olabilir; cloud'a göndermeden önce kontrol).

6. allowedDomains boşsa BrowserAgent çalışmaz.
   vault.plist'te en az bir domain tanımlanmalıdır.
```

---

## 14. Görev Döngüsü & Kullanıcı Etkileşimi

### 14.1 Görev Yaşam Döngüsü

```
[KULLANICI GİRİŞİ — SwiftUI Chat veya Menu Bar]
         │
         ▼
[ORCHESTRATOR: Task Classifier]
  → Kategori belirle (9 kategori)
  → Karmaşıklık puanla (1–5)
  → Sensitivity sınıflandır (public/internal/confidential)
  → Guard'a PRIVACY_CHECK sinyali gönder
         │
         ▼
[GUARD: Privacy Karar]
  → PRIVACY_PASS / DESENSITIZE / BLOCK
  → Orchestrator routing kararını günceller
         │
         ▼
[PLANNER: Decomposition]
  → Görevi alt adımlara böl
  → Her adım için araç / MCP / CUA seç
  → Belirsizlik → CLARIFY_REQUEST (max 1 soru)
  → PLAN_READY
         │
         ▼
[ORCHESTRATOR: Onay Eşiği]
  → complexity >= approval_threshold → planı göster; onay iste
  → Onay geldi → Executor'a ilet
         │
         ▼
[EXECUTOR: Tool / MCP / CUA]
  → Araçları çalıştır (sıralı veya paralel)
  → Her adımda UI'ya ilerleme gönder
  → REVIEW_REQUEST
         │
         ▼
[CRITIC: Denetim]
  → 0–10 puan
  → PASS (≥7) → TASK_COMPLETE
  → FAIL (<7) → SELF_CORRECTION (max 3 retry)
         │
         ▼
[ORCHESTRATOR: Sonuç]
  → SwiftUI'ya gönder; kullanıcıya göster
  → Memory'ye kaydet
  → Git commit
```

### 14.2 Karmaşıklık Puanı

| Puan | Kriter | Örnek |
|------|--------|-------|
| 1 | Tek araç, tek adım | "report.txt dosyasını oku" |
| 2 | 1–2 araç, 2–3 adım | "Web'de ara, dosyaya yaz" |
| 3 | Birden fazla araç, 4–6 adım | "Araştır, özetle, rapor oluştur" |
| 4 | Paralel alt görevler | "3 kaynaktan veri çek, karşılaştır" |
| 5 | Karmaşık iş akışı + belirsizlik | "Projeyi analiz et, geliştir, test et" |

### 14.3 UI — İlerleme Raporlama

SwiftUI'da her araç çağrısından önce ve sonra güncelleme:

```swift
// ChatView'da live update
struct TaskProgressView: View {
    @ObservedObject var task: ActiveTask

    var body: some View {
        ForEach(task.steps) { step in
            HStack {
                Image(systemName: step.status.icon)
                    .foregroundColor(step.status.color)
                Text(step.description)
                if step.status == .running {
                    ProgressView().scaleEffect(0.7)
                }
            }
        }
    }
}
```

---

## 15. Hafıza Mimarisi — L1/L2 + Privacy Split

### 15.1 L1: Aktif Bellek (RAM)

```swift
actor MemoryAgent {
    // L1 — Actor isolated state; SharedArrayBuffer yok
    private var activeContext: CircularBuffer<ThinkBlock>  // son 5
    private var agentStates: [AgentID: AgentState]
    private var providerMetrics: [ProviderID: ProviderMetrics]
    private var mcpManifests: [String: MCPManifest]
}
```

| Bileşen | Yapı | Kapasite |
|---------|------|---------|
| Active Context | `CircularBuffer<ThinkBlock>` | Son 5 think block |
| Agent States | `[AgentID: AgentState]` | Tüm ajanlar |
| Provider Metrics | `[ProviderID: ProviderMetrics]` | Latency, maliyet |
| MCP Manifests | `[String: MCPManifest]` | Sunucu araç listeleri |

### 15.2 L2: Kalıcı Bellek (Disk)

```
~/.eliteagent/
├── KNOWLEDGE_BASE.md          cloud-safe; PII çıkarılmış
├── KNOWLEDGE_BASE-FULL.md     local-only; PII dahil; Guard + Memory erişir
├── THINK_LOG.md               LLM think block geçmişi (son 100)
├── DEVLOG.md                  oturum özetleri (otonom yazılır)
├── task_history.jsonl         görev özetleri + provider bilgisi
├── cost_ledger.json           günlük maliyet takibi
├── provider_health.json       son health check + latency
├── audit.log                  tüm araç + LLM çağrıları
└── security.log               güvenlik eventleri
```

### 15.3 L2 Retrieval

Regex tabanlı keyword eşleşmesi; embedding veya vektör veritabanı yok.

```swift
func retrieve(keywords: [String], maxBlocks: Int = 3) async -> [String] {
    let patterns = keywords.map { NSRegularExpression(pattern: $0) }
    // FileHandle ile satır satır; tüm dosyayı belleğe yüklemez
    return try await searchFile(KNOWLEDGE_BASE_FULL, patterns: patterns, limit: maxBlocks)
}
```

Provider tipine göre dosya seçimi:
- Local LLM → `KNOWLEDGE_BASE-FULL.md`
- Cloud LLM → `KNOWLEDGE_BASE.md`

### 15.4 Pruning

- L1 Active Context: 5. think block → L2'ye taşın
- L2 THINK_LOG: 100 entry üzerinde → KNOWLEDGE_BASE'e özetlenerek sıkıştır
- task_history.jsonl: 30 günden eski → arşivle

### 15.5 Bellek Evrim Notu

Regex retrieval sistemi ne zaman yetersiz kalır ve grafik belleğe geçiş değerlendirilir:

| Kriter | Eşik |
|--------|------|
| Birikmiş görev | > 500 |
| Retrieval isabetsizlik oranı | > %30 |
| Çok adımlı ilişki sorgusu oranı | > %20 |

Bu üç koşul aynı anda karşılanırsa grafik bellek katmanı değerlendirilir. Seçilecek çözüm harici bağımlılık olmadan SPM üzerinden entegre edilebilir olmalıdır.

---

## 16. Yetenek Tanımları — Skill Engine

### 16.1 FS_ATOMIC

```swift
struct AtomicFileWriter {
    func write(_ data: Data, to url: URL) throws {
        let tempURL = url.deletingLastPathComponent()
            .appendingPathComponent(UUID().uuidString)
        try data.write(to: tempURL, options: .atomic)
        try FileManager.default.moveItem(at: tempURL, to: url)
    }
}
```

### 16.2 XPC_SANDBOX (shell aracı için)

```
İzin verilen dizinler : ~/Documents/eliteagent/ ve /tmp/eliteagent/
Yasak komutlar        : rm -rf /, mkfs, dd, shutdown, reboot, curl | bash,
                        wget | sh, chmod 777, chown root
Timeout               : 120 saniye (process.terminate())
XPC entitlement       : com.apple.security.temporary-exception — yalnızca izinli dizinler
```

### 16.3 SELF_CORRECTION

```
Hata alındı
  → Critic'e REVIEW_FAIL gönderilir
  → Critic root cause analizi yapar (MLX ile)
  → Planner'a geri bildirim
  → Revize plan → Executor
  → Retry sayacı artar
  → Retry ≥ 3 → HUMAN_ESCALATION

HUMAN_ESCALATION:
  1. Tüm Actor'lar .idle durumuna geçer
  2. SwiftUI'da modal uyarı gösterilir:
     "Görev 3 denemede tamamlanamadı. Son hata: {hata}"
     [Görevi İptal Et] [Baştan Başlat] [Manuel Talimat Ver]
  3. Kullanıcı seçim yapana kadar sistem bekler
```

---

## 17. AI Entegrasyonu — The Thinking Protocol

### 17.1 Think Block Parse

```swift
func parseResponse(_ raw: String) -> (thinkBlock: String?, actionable: String) {
    let pattern = #/<think>([\s\S]*?)<\/think>/#
    if let match = raw.firstMatch(of: pattern) {
        let think = String(match.output.1).trimmingCharacters(in: .whitespacesAndNewlines)
        let actionable = raw.replacing(pattern, with: "").trimmingCharacters(in: .whitespacesAndNewlines)
        if actionable.isEmpty {
            // Actionable yok → SELF_CORRECTION; uydurma yapılmaz
            Task { await emit(.error(code: "EMPTY_ACTIONABLE", retry: true)) }
        }
        return (think, actionable)
    }
    return (nil, raw)
}
```

### 17.2 max_tokens Think Buffer Kuralı

```
Reasoning modeli (capabilities içinde .think olan provider):
  maxTokens_gönderilecek = task.maxTokens × 1.5

Non-reasoning modeller: çarpan uygulanmaz (× 1.0)
```

### 17.3 Görev Tipine Göre Varsayılan max_tokens

| Karmaşıklık | Varsayılan | Think buffer sonrası |
|-------------|-----------|---------------------|
| 1 | 1.024 | 1.536 |
| 2 | 2.048 | 3.072 |
| 3 | 4.096 | 6.144 |
| 4 | 6.144 | 9.216 |
| 5 | 8.192 | 12.288 |

### 17.4 Prompt Template Sözleşmeleri

**Planner:**
```
Sen Elite Agent'ın Planner ajanısın.
Araçlar: {toolManifest}
Mevcut durum: {projectState}
Geçmiş bağlam: {retrievedContext}
Görev: {taskDescription}

Yanıt YALNIZCA JSON:
{
  "complexity": 1-5,
  "sensitivityLevel": "public|internal|confidential",
  "needsClarification": bool,
  "clarificationQuestion": string|null,
  "steps": [
    { "stepID": "s1", "type": "tool|mcp|cua",
      "toolID": "...", "params": {}, "dependsOn": [] }
  ]
}
```

**Executor:**
```
Sen Elite Agent'ın Executor ajanısın.
Plan: {planJSON}
Sandbox kısıtları: ~/Documents/eliteagent/ ve /tmp/eliteagent/ dışına yazma yasak.
Yasak komutlar: {forbiddenPatterns}
```

**Critic:**
```
Sen Elite Agent'ın Critic ajanısın.
Görev: {taskDescription}
Executor çıktısı: {executorOutput}
Başarı kriterleri: {successCriteria}

Yanıt YALNIZCA JSON:
{ "score": 0-10, "passed": bool,
  "rootCause": string|null, "suggestedFix": string|null }
```

---

## 18. Güvenlik & Sandbox — XPC

### 18.1 Kaynak Kısıtlamaları

- **CPU:** Foundation `Process` timeout 120 sn; aşılırsa `process.terminate()`
- **Disk:** XPC entitlement ile yalnızca izinli dizinler
- **Network:** URLSession ile yalnızca vault.plist'te tanımlı endpoint'lere
- **Bellek:** L1 Actor state toplam 64 MB sınırı

### 18.2 Prompt Injection Koruması

```swift
struct PromptSanitizer {
    static let dangerousPatterns = [
        "ignore previous instructions",
        "you are now",
        "disregard your",
        "act as if",
        "forget everything"
    ]

    func sanitize(_ input: String) -> (clean: String, flagged: Bool) {
        let lowered = input.lowercased()
        let flagged = Self.dangerousPatterns.contains { lowered.contains($0) }
        if flagged {
            Task { await SecurityLog.write("[SECURITY_FLAG] prompt_injection_attempt") }
        }
        return (input, flagged)
    }
}
```

### 18.3 Keychain Secret Yönetimi

```swift
// HMAC secret ve API key'ler Keychain'de
struct KeychainManager {
    func store(key: String, value: String) throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: "com.eliteagent",
            kSecAttrAccount as String: key,
            kSecValueData as String: Data(value.utf8)
        ]
        SecItemAdd(query as CFDictionary, nil)
    }

    func retrieve(key: String) throws -> String {
        // Keychain'den okur; vault.plist'te düz metin saklanmaz
    }
}
```

### 18.4 Audit Log

```
Her satır: [ISO_TIMESTAMP] [LEVEL] [AGENT] MESSAGE

audit.log    → tüm araç + LLM + MCP + CUA çağrıları
security.log → SECURITY_FLAG, AGENT_ISOLATION, GUARD kararları
```

---

## 19. Konfigürasyon — vault.plist

API key'ler `vault.plist`'te **saklanmaz**. vault.plist yalnızca endpoint ve ayar bilgisi tutar. API key'ler Keychain'dedir.

`vault.plist` git'e eklenmez. `.gitignore`'a dahil edilmesi zorunludur.

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN"
  "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>providers</key>
  <dict>
    <key>local</key>
    <array>
      <dict>
        <key>id</key><string>mlx-r1-32b</string>
        <key>type</key><string>mlx</string>
        <key>modelName</key><string>deepseek-r1-32b-mlx</string>
        <key>capabilities</key>
        <array><string>think</string><string>code</string><string>general</string></array>
        <key>maxContextTokens</key><integer>128000</integer>
      </dict>
      <dict>
        <key>id</key><string>ollama-llama3-8b</string>
        <key>type</key><string>ollama</string>
        <key>endpoint</key><string>http://localhost:11434</string>
        <key>modelName</key><string>llama3:8b</string>
        <key>capabilities</key>
        <array><string>code</string><string>fast</string><string>general</string></array>
        <key>maxContextTokens</key><integer>8192</integer>
      </dict>
    </array>
    <key>cloud</key>
    <array>
      <dict>
        <key>id</key><string>claude-sonnet</string>
        <key>type</key><string>anthropic</string>
        <key>endpoint</key><string>https://api.anthropic.com</string>
        <key>keychainKey</key><string>com.eliteagent.api.anthropic</string>
        <key>modelName</key><string>claude-sonnet-4-5</string>
        <key>costPer1KTokens</key><real>0.003</real>
        <key>maxContextTokens</key><integer>200000</integer>
      </dict>
      <!-- OpenRouter: tek endpoint, 200+ model -->
      <dict>
        <key>id</key><string>openrouter-r1</string>
        <key>type</key><string>openrouter</string>
        <key>endpoint</key><string>https://openrouter.ai/api/v1</string>
        <key>keychainKey</key><string>com.eliteagent.api.openrouter</string>
        <key>modelName</key><string>deepseek/deepseek-r1</string>
        <key>capabilities</key>
        <array><string>think</string><string>code</string><string>general</string></array>
        <key>costPer1KTokens</key><real>0.0008</real>
        <key>maxContextTokens</key><integer>65536</integer>
      </dict>
      <dict>
        <key>id</key><string>gpt-4o-mini</string>
        <key>type</key><string>openai</string>
        <key>endpoint</key><string>https://api.openai.com</string>
        <key>keychainKey</key><string>com.eliteagent.api.openai</string>
        <key>modelName</key><string>gpt-4o-mini</string>
        <key>costPer1KTokens</key><real>0.00015</real>
        <key>maxContextTokens</key><integer>128000</integer>
      </dict>
    </array>
  </dict>

  <key>routing</key>
  <dict>
    <!-- local_first | cloud_only | hybrid -->
    <key>strategy</key><string>local_first</string>
    <key>maxDailyCostUSD</key><real>5.0</real>
    <key>healthCheckIntervalMs</key><integer>30000</integer>
    <key>maxParallelRequests</key><integer>2</integer>
    <!-- Hibrit profil: complexity >= hybridCloudThreshold → cloud -->
    <key>hybridCloudThreshold</key><integer>3</integer>
  </dict>

  <key>agents</key>
  <dict>
    <key>planner</key>
    <dict>
      <key>preferred</key><string>mlx-r1-32b</string>
      <key>fallback</key>
      <array><string>claude-sonnet</string><string>gpt-4o-mini</string></array>
    </dict>
    <key>executor</key>
    <dict>
      <key>preferred</key><string>mlx-llama3-8b</string>
      <key>fallback</key><array><string>gpt-4o-mini</string></array>
    </dict>
    <key>critic</key>
    <dict>
      <key>preferred</key><string>mlx-llama3-8b</string>
      <key>fallback</key><array><string>mlx-r1-8b</string></array>
    </dict>
    <key>guard</key>
    <dict>
      <key>preferred</key><string>mlx-r1-8b</string>
      <!-- cloud fallback yok — hardcode yasak -->
    </dict>
  </dict>

  <key>task</key>
  <dict>
    <key>approvalThreshold</key><integer>3</integer>
    <key>clarificationTimeoutMs</key><integer>300000</integer>
  </dict>

  <key>git</key>
  <dict>
    <key>enabled</key><true/>
    <key>autoCommit</key><true/>
    <key>remoteEnabled</key><false/>
  </dict>

  <key>cua</key>
  <dict>
    <key>enabled</key><false/>
    <key>maxSteps</key><integer>20</integer>
    <key>clickApproval</key><true/>
    <key>allowedApps</key>
    <array><string>com.apple.Safari</string></array>
    <key>screenshotMaxWidth</key><integer>1280</integer>
    <key>screenshotMaxHeight</key><integer>720</integer>
    <key>screenshotQuality</key><integer>70</integer>
  </dict>

  <key>browser</key>
  <dict>
    <!-- BrowserAgent: Safari native tarayıcı kontrolü -->
    <key>enabled</key><false/>
    <!-- Boşsa BrowserAgent çalışmaz -->
    <key>allowedDomains</key>
    <array>
      <string>localhost</string>
      <string>127.0.0.1</string>
    </array>
    <!-- JavaScript inject her zaman onay ister; değiştirilemez -->
    <key>jsApprovalRequired</key><true/>
    <!-- Form submit ayrıca onay ister -->
    <key>submitApprovalRequired</key><true/>
  </dict>

  <key>privacy</key>
  <dict>
    <key>enabled</key><true/>
    <key>modelCheckEnabled</key><true/>
    <key>modelCheckProvider</key><string>mlx-r1-8b</string>
    <key>memorySplitEnabled</key><true/>
    <!-- Cache: aynı payload için Guard tekrar çalıştırılmaz -->
    <key>cacheTTLSeconds</key><integer>300</integer>
    <key>cacheMaxEntries</key><integer>500</integer>
    <!-- cloud_only profilde PRIVACY_BLOCK davranışı: warn | desensitize | cancel -->
    <key>cloudOnlyBlockBehavior</key><string>warn</string>
    <key>blockPatterns</key>
    <array>
      <string>ignore previous instructions</string>
      <string>api_key</string>
    </array>
    <key>desensitizePatterns</key>
    <array>
      <dict>
        <key>label</key><string>tc_kimlik</string>
        <key>regex</key><string>\b[1-9][0-9]{10}\b</string>
        <key>replace</key><string>[TC_KIMLIK]</string>
      </dict>
      <dict>
        <key>label</key><string>telefon</string>
        <key>regex</key><string>(\+90|0)[\s\-]?5[0-9]{9}</string>
        <key>replace</key><string>[TELEFON]</string>
      </dict>
    </array>
  </dict>

  <key>inference</key>
  <dict>
    <!-- Kullanıcı aktifken yeni inference başlatma -->
    <key>pauseOnUserInteraction</key><true/>
    <!-- Bellek baskısında otomatik küçük modele geç -->
    <key>dynamicDownscalingEnabled</key><true/>
    <!-- Downscale sonrası normal modele dönmek için bekleme -->
    <key>downscaleRecoverySeconds</key><integer>60</integer>
  </dict>

  <key>mcpServers</key>
  <array>
    <dict>
      <key>serverID</key><string>xcode-mcp</string>
      <key>displayName</key><string>Xcode MCP</string>
      <key>transport</key><string>stdio</string>
      <key>command</key><string>npx xcode-mcp</string>
      <key>defaultApproval</key><true/>
      <key>noApprovalTools</key>
      <array><string>get_build_errors</string><string>list_schemes</string></array>
      <key>xcodeAllowedSchemes</key>
      <array><string>MyApp</string></array>
    </dict>
    <dict>
      <key>serverID</key><string>figma-mcp</string>
      <key>displayName</key><string>Figma MCP</string>
      <key>transport</key><string>sse</string>
      <key>url</key><string>https://figma-mcp.example.com/sse</string>
      <key>defaultApproval</key><false/>
    </dict>
    <!-- chrome-mcp kaldırıldı. Tarayıcı kontrolü için BrowserAgent kullanılır (Madde 13.6) -->
  </array>
</dict>
</plist>
```

---

## 20. Kurulum & Dağıtım

Elite Agent bir yazılım ürünüdür. `setup.sh` ve `bootstrap.js` yoktur.

### 20.1 Proje Yapısı (Xcode)

```
EliteAgent.xcodeproj
├── Sources/
│   ├── App/
│   │   ├── EliteAgentApp.swift          @main; SwiftUI App
│   │   ├── MenuBarController.swift      NSStatusItem yönetimi
│   │   └── ChatWindowView.swift         Ana SwiftUI arayüzü
│   │
│   ├── Core/
│   │   ├── Orchestrator.swift           @MainActor; sinyal merkezi
│   │   ├── Agents/
│   │   │   ├── PlannerAgent.swift
│   │   │   ├── ExecutorAgent.swift
│   │   │   ├── CriticAgent.swift
│   │   │   ├── MemoryAgent.swift
│   │   │   └── GuardAgent.swift
│   │   │
│   │   ├── Bridge/
│   │   │   ├── HarpsichordBridge.swift
│   │   │   ├── MLXProvider.swift
│   │   │   ├── OllamaProvider.swift
│   │   │   └── CloudProvider.swift
│   │   │
│   │   ├── Tools/
│   │   │   ├── ToolEngine.swift         Tool tanımlarını yükler
│   │   │   ├── FileSystemTool.swift
│   │   │   ├── WebTool.swift
│   │   │   └── DataTool.swift
│   │   │
│   │   ├── MCP/
│   │   │   ├── MCPGateway.swift
│   │   │   └── MCPTransport.swift       stdio + SSE
│   │   │
│   │   ├── Memory/
│   │   │   ├── L1Cache.swift
│   │   │   ├── L2Storage.swift
│   │   │   └── GitStateEngine.swift
│   │   │
│   │   ├── CUA/
│   │   │   ├── CUALayer.swift
│   │   │   └── AXUIBridge.swift
│   │   │
│   │   ├── Browser/
│   │   │   ├── BrowserAgent.swift       Safari AXUIElement + WebKit kontrolü
│   │   │   └── SafariJSBridge.swift     AppleScript üzerinden JS inject
│   │   │
│   │   ├── Privacy/
│   │   │   ├── RuleBasedChecker.swift
│   │   │   └── ModelBasedChecker.swift
│   │   │
│   │   └── Security/
│   │       ├── SignalSigner.swift       HMAC-SHA256
│   │       ├── PromptSanitizer.swift
│   │       └── KeychainManager.swift
│   │
│   ├── XPCService/                      Ayrı target; shell sandbox
│   │   └── SandboxXPCService.swift
│   │
│   └── Resources/
│       ├── tools/                       JSON tool tanımları
│       └── vault.example.plist
│
├── Tests/
│   ├── UnitTests/
│   └── E2ETests/
│
└── Installer/
    ├── build_installer.sh               .pkg oluşturma scripti
    ├── launchd/
    │   └── com.eliteagent.daemon.plist  launchd unit
    └── postinstall                      Kurulum sonrası script
```

### 20.2 Daemon — launchd

```xml
<!-- /Library/LaunchAgents/com.eliteagent.daemon.plist -->
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN"
  "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key>
  <string>com.eliteagent.daemon</string>

  <key>ProgramArguments</key>
  <array>
    <string>/Applications/EliteAgent.app/Contents/MacOS/EliteAgent</string>
    <string>--daemon</string>
  </array>

  <key>RunAtLoad</key><true/>
  <key>KeepAlive</key><true/>

  <key>StandardOutPath</key>
  <string>/Users/Shared/EliteAgent/daemon.log</string>
  <key>StandardErrorPath</key>
  <string>/Users/Shared/EliteAgent/daemon_error.log</string>

  <key>EnvironmentVariables</key>
  <dict>
    <key>ELITEAGENT_HOME</key>
    <string>/Users/Shared/EliteAgent</string>
  </dict>
</dict>
</plist>
```

### 20.3 Kurulum Adımları (Installer Paketi)

```
1. Installer başlatılır (.pkg çift tıklama)

2. Sistem kontrolleri:
   → macOS 14.0 (Sonoma) veya üzeri
   → Apple Silicon M serisi
   → Xcode Command Line Tools mevcut mu?

3. Uygulama bundle kopyalanır:
   → /Applications/EliteAgent.app

4. Dizinler oluşturulur:
   → ~/.eliteagent/
   → ~/.eliteagent/models/
   → ~/.eliteagent/logs/
   → ~/.eliteagent/tools/

5. vault.example.plist kopyalanır:
   → ~/.eliteagent/vault.plist
   (API key alanları boş; kullanıcı dolduracak)

6. Keychain'e HMAC secret yazılır:
   → openssl rand -hex 32 ile üretilir
   → com.eliteagent.hmac_secret olarak eklenir

7. launchd daemon kurulur:
   → plist /Library/LaunchAgents/ altına kopyalanır
   → launchctl load com.eliteagent.daemon

8. İlk çalıştırma:
   → EliteAgent.app açılır
   → vault.plist'te boş alan varsa kurulum sihirbazı başlar
   → MLX model indirme başlatılır (~5-65 GB; background)
   → İndirme tamamlanınca daemon tam kapasiteye geçer
```

### 20.4 Gereksinimler

```
macOS    : 14.0 Sonoma veya üzeri
Donanım  : Apple Silicon (M1 / M2 / M3 / M4 serisi)
Disk     : Minimum 20 GB boş alan (Cloud-Only profil)
           Minimum 100 GB boş alan (local model barındırmak için)
Xcode    : 15.0 veya üzeri (build için)
```

**Profil bazlı RAM gereksinimleri:**

```
Cloud-Only profil  : 8 GB Unified Memory yeterli
Hibrit profil      : 16 GB Unified Memory (8B model)
Local-First (8B)   : 16 GB Unified Memory
Local-First (32B)  : 96 GB+ Unified Memory önerilir
                     (R1-32B gerçek tüketim ~120 GB gözlemlenmiştir;
                      64 GB'ta swap devreye girebilir ve sistem yavaşlar)
```

Kurulum sihirbazı cihazın RAM'ini otomatik okuyarak profil önerisi yapar (bkz. Madde 6.9).

---

## 21. Yapım Takvimi

| # | Özellik | Bileşen | Bağımlılık | Süre (gün) | Kabul Kriteri |
|---|---------|---------|------------|-----------|---------------|
| **— TEMEL ALTYAPI —** | | | | | |
| 1 | Xcode projesi + Swift Package kurulumu | Proje | — | 1 | Build hatasız tamamlanır |
| 2 | Actor iskelet (5 ajan) | Tüm Ajanlar | 1 | 2 | 5 Actor paralel; birbirini bloke etmez |
| 2a | Actor Deadlock Prevention (timeout + yön kuralları) | Orchestrator | 2 | 2 | Sinyal timeout çalışır; yasak yön → derleme hatası |
| 3 | Sinyal sistemi (Signal struct + HMAC) | Orchestrator | 2 | 2 | Sinyal gönder/al; sahte sinyal reddedilir |
| 4 | vault.plist okuma + Keychain entegrasyonu | Config | 1 | 2 | Eksik key → anlamlı hata; API key Keychain'den |
| 5 | launchd daemon + Menu Bar temel UI | App | 1 | 3 | Sistem açılışında başlar; Menu Bar görünür |
| **— LLM BRIDGE —** | | | | | |
| 6 | MLX Provider (model yükleme + inference) | Bridge | 2 | 4 | R1-32B think block dahil parse; M serisi çalışır |
| 7 | Ollama Provider (Metal REST) | Bridge | 2 | 2 | Ollama'ya istek; yanıt parse |
| 8 | Cloud Provider (OpenAI-compat URLSession) | Bridge | 2 | 2 | Claude/GPT/OpenRouter yanıt parse |
| 8a | OpenRouter Provider (model path formatı) | Bridge | 8 | 1 | deepseek/deepseek-r1 path çalışır; think-block parse |
| 9 | Harpsichord Bridge routing (profil bazlı) | Bridge | 6, 7, 8 | 3 | 3 profil doğru çalışır; fallback zinciri |
| 9a | Dynamic Downscaling (memory pressure) | Bridge | 9 | 2 | elevated → 8B'ye geç; normal → geri dön |
| 9b | Pause on User Interaction | Bridge | 9 | 1 | NSEvent monitor; 3 sn boşlukta inference devam eder |
| 9c | Kurulum sihirbazı profil önerisi | App | 4 | 1 | RAM okur; Madde 6.9 tablosuna göre öneri yapar |
| 10 | Sensitivity routing (confidential block) | Bridge | 9 | 1 | confidential → cloud engellenir |
| 11 | Paralel sorgu limiti N=2 | Bridge | 9 | 1 | 3. istek kuyruğa alınır |
| 12 | cost_ledger maliyet takibi | Bridge | 9 | 1 | Her cloud çağrısı Decimal olarak kaydedilir |
| **— TOOL ENGINE —** | | | | | |
| 13 | Tool Engine: JSON tanım yükleme | Tool Engine | 2 | 1 | tools/ dizininden otomatik yüklenir |
| 14 | read_file + write_file (AtomicFileWriter) | Tool Engine | 13 | 2 | Atomic write; izin dışı → ret |
| 15 | XPC Sandbox Service | XPC | 1 | 3 | shell komutu XPC izolasyonunda; yasak → ret |
| 16 | web_search (DuckDuckGo URLSession) | Tool Engine | 13 | 2 | Sonuç parse; timeout 10 sn |
| 17 | web_fetch | Tool Engine | 13 | 1 | HTML → plaintext; timeout |
| 18 | json_parse, grep, summarize | Tool Engine | 13 | 2 | 3 araç çalışır |
| **— PRIVACY GUARD —** | | | | | |
| 19 | Guard Actor iskeleti | Guard | 2 | 2 | Sinyal alır/gönderir; cloud çağrısı yapamaz |
| 20 | Rule-based check (NSRegularExpression) | Guard | 19 | 2 | TC kimlik / IBAN → BLOCK < 10 ms |
| 21 | Desensitize motoru | Guard | 20 | 2 | Maskeleme doğru; [TC_KIMLIK] vb. |
| 22 | Model-based check (MLX R1-8B) | Guard | 19, 6 | 2 | PII tespiti doğru; timeout → PASS + WARN |
| 23 | Auto-classify tasks | Orchestrator + Guard | 19, 4 | 1 | confidential_task_keywords eşleşmesi |
| 24 | Privacy check entegrasyonu (tüm araçlar) | Guard | 20, 13 | 2 | read_file, write_file, mcp_call Guard'dan geçer |
| **— GÖREV DÖNGÜSÜ —** | | | | | |
| 25 | Task Classifier (9 kategori) | Orchestrator | 3 | 2 | 9 kategori doğru |
| 26 | Karmaşıklık puanlama | Planner | 25 | 1 | 1–5 puan doğru |
| 27 | Planner prompt şablonu + JSON plan | Planner | 9, 26 | 2 | JSON plan çıktısı şemaya uygun |
| 28 | Clarification protokolü | Orchestrator | 25 | 1 | 1 soru; 300 sn timeout |
| 29 | SwiftUI ilerleme güncelleme | App | 5, 2 | 2 | Her araç adımı UI'da görünür |
| 30 | Onay eşiği akışı | Orchestrator | 26 | 1 | Karmaşıklık ≥ eşik → modal onay |
| **— HAFIZA & GIT —** | | | | | |
| 31 | Memory Actor (L1 — Actor isolated) | Memory | 2 | 3 | Diğer Actor'lar doğrudan erişemez |
| 32 | L1 Active Context + Think Log Buffer | Memory | 31 | 2 | 5 think block circular buffer |
| 33 | L2 Retrieval (FileHandle satır bazlı) | Memory | 31 | 3 | 1.000 kayıtta < 50 ms; 3 blok |
| 34 | Provider tipine göre KNOWLEDGE_BASE seçimi | Memory | 33, 9 | 1 | Local → FULL; cloud → safe |
| 35 | Context pruning | Memory | 33 | 2 | 5. adımda L2; 100. entry'de özet |
| 36 | KNOWLEDGE_BASE ikili dosya (Privacy Split) | Memory + Guard | 31, 20 | 3 | PII → FULL'a tam; safe'e maskeli |
| 37 | Git State Engine (Foundation.Process) | Memory | 2 | 2 | write_file sonrası commit oluşur |
| 38 | Git privacy sync commit | Memory + Guard | 36, 37 | 1 | Sync sonrası her iki dosya commit'lenir |
| 39 | Git revert protokolü | Orchestrator + Memory | 37 | 2 | Kullanıcı onaylı geri alma çalışır |
| **— GÜVENLİK —** | | | | | |
| 40 | Prompt injection sanitizer | Orchestrator | 3 | 2 | 10 pattern SECURITY_FLAG |
| 41 | Audit log + security.log | Orchestrator | 2 | 1 | Tüm araç + LLM + Guard loglanır |
| 42 | Log rotasyon | Memory | 41 | 1 | audit.log > 100 MB → arşivle |
| **— CRITIC & SELF-CORRECTION —** | | | | | |
| 43 | Critic puanlama + JSON çıktı | Critic | 9, 2 | 2 | Şemaya uygun; < 7 → REVIEW_FAIL |
| 44 | Self-Correction döngüsü | Critic + Planner | 43, 27 | 2 | 3 retry; başarı paternleri birikir |
| 45 | HUMAN_ESCALATION SwiftUI modal | App | 44 | 1 | Modal gösterilir; 3 seçenek |
| **— E2E TESTLER —** | | | | | |
| 46 | E2E: araştırma görevi | Tüm sistem | 16, 14, 27, 43 | 2 | "BBC araştır, rapor.txt yaz" < 180 sn |
| 47 | E2E: privacy görevi | Tüm sistem + Guard | 24, 36, 46 | 2 | Finansal belge → cloud'a PII gitmiyor |
| 48 | E2E: 3 araçlı iş akışı | Tüm sistem | 46 | 1 | web_search + web_fetch + write_file otonom |
| **— MCP GATEWAY —** | | | | | |
| 49 | MCP Gateway: altyapı (URLSession + Process) | MCP | 2 | 3 | stdio + SSE; JSON-RPC 2.0 doğru |
| 50 | MCP başlatma + manifest yükleme | MCP | 49 | 2 | 3 sunucu başlar; manifest L1'e |
| 51 | xcode-mcp | MCP | 50 | 3 | build_project, get_build_errors çalışır |
| 52 | figma-mcp | MCP | 50 | 3 | get_file, get_component, export_asset |
| 53 | BrowserAgent: AXUIElement katmanı | Browser | 2 | 3 | Safari tab/URL/buton AXUIElement ile kontrol |
| 54 | BrowserAgent: SafariJSBridge (JS inject) | Browser | 53 | 3 | JavaScript çalışır; DOM sorgusu döner |
| 55 | BrowserAgent: fillForm + navigate | Browser | 53, 54 | 2 | Form doldurma ve sayfa navigasyonu otonom |
| 56 | BrowserAgent güvenlik kısıtları | Browser | 53 | 1 | allowedDomains dışı → ret; JS/submit onay zorunlu |
| 57 | MCP_SERVER_DOWN akışı | Orchestrator | 49 | 1 | 3 timeout → offline; SwiftUI uyarı |
| 58 | MCP onay akışı | Executor | 50 | 1 | defaultApproval → modal onay |
| 59 | MCP + Privacy Check | Guard + MCP | 24, 50 | 2 | mcp_call payload Guard'dan geçer |
| 60 | MCP audit log | Orchestrator | 41, 50 | 1 | Tüm MCP çağrıları loglanır |
| **— CUA KATMANI —** | | | | | |
| 58 | CUA Adım 1: AXUIElement tree okuma | CUA | 53 | 3 | Accessibility tree JSON döner |
| 59 | CUA Adım 2: observe→decide→act döngüsü | CUA | 58 | 4 | Buton tıklama görevi otonom |
| 60 | CUA Adım 3: tam durum makinesi + max_steps | CUA | 59 | 5 | 5 adımlı form doldurma otonom |
| 61 | CUA güvenlik kısıtları | CUA | 58 | 1 | allowedApps dışı → ret; type modal |
| 62 | CUA + Privacy Check | Guard + CUA | 24, 58 | 2 | screenshot Guard'dan geçer |
| **— İLERİ ÖZELLİKLER —** | | | | | |
| 63 | Multi-provider paralel sorgu + Critic seçimi | Bridge + Critic | 11, 43 | 2 | Puanlama doğru; latency tiebreaker |
| 64 | DEVLOG oto-yazım | Critic + Memory | 43, 31 | 2 | Her oturum sonrası özet |
| 65 | KNOWLEDGE_BASE öz-öğrenme | Memory | 35, 36 | 3 | Başarı paternleri birikir ve kullanılır |
| 66 | SwiftUI Dashboard (tam) | App | 43, 12 | 3 | Ajan, provider, MCP, CUA, maliyet |
| **— REGRESYON & KALİTE —** | | | | | |
| 67 | E2E: Figma → Xcode → build | Tüm sistem | 51, 52 | 2 | "Figma component → Xcode entegre → build" |
| 68 | E2E: karmaşık araştırma | Tüm sistem | 48, 65 | 2 | "3 kaynaktan araştır, rapor" < 5 dk |
| 69 | Regresyon test paketi | QA | 46–68 | 3 | Tüm ACCEPTED senaryolar geçer |
| 70 | Performans profili | Monitor | 69 | 2 | Sinyal < 500 ms; Guard < 3000 ms; MCP/CUA < 60 sn |

### 21.2 Kritik Yol

```
1 → 2 → 3 → 4 → 5 → 6 → 9 → 13 → 14 → 16 → 25 → 27 → 31 → 33 → 43 → 46
```

Bu 16 özellik tamamlandığında sistem temel araştırma görevi yapabilir.

Privacy Guard kritik yolu:
```
19 → 20 → 21 → 24 → 36 → 47
```

---

## 22. Runbook — Operasyonel Hata Giderme

### 22.1 MLX Model Yüklenmiyor

```
Belirti  : Bridge status = .error; "Model not loaded" hatası
Kontrol  : ~/.eliteagent/models/ dizininde model dosyası var mı?
Çözüm A  : Model yeniden indir (EliteAgent → Ayarlar → Modeller)
Çözüm B  : MLX formatı yoksa vault.plist'te ollama provider'a geçiş
Log      : audit.log → [BRIDGE] MLX_LOAD_ERROR
```

### 22.2 launchd Daemon Başlamıyor

```
Kontrol  : launchctl list | grep eliteagent
Çözüm    : launchctl unload + load com.eliteagent.daemon
Log      : /Users/Shared/EliteAgent/daemon_error.log
```

### 22.3 Guard Timeout Aşımı

```
Belirti  : [WARN] GUARD_TIMEOUT; PRIVACY_PASS varsayıldı
Anlam    : MLX R1-8B model yavaş; 3000 ms aşıldı
Çözüm A  : Model önbelleği ısıtılmış değil; ilk çağrı yavaş normaldir
Çözüm B  : Guard modelini daha küçük bir modele değiştir (vault.plist)
```

### 22.4 XPC Sandbox Reddi

```
Belirti  : SandboxError.forbiddenCommand
Kontrol  : Hangi komut reddedildi? → security.log
Çözüm    : Komut yasak listedeyse → HUMAN_ESCALATION; manuel yürütülmeli
```

### 22.5 MCP Sunucu Yanıt Vermiyor

```
Belirti  : MCP_SERVER_DOWN; SwiftUI sarı uyarı
Kontrol  : npx xcode-mcp --version (terminalde)
Çözüm A  : npm install -g xcode-mcp (güncelle)
Çözüm B  : vault.plist'ten sunucuyu geçici devre dışı bırak
```

### 22.6 Keychain Erişim Reddi

```
Belirti  : KeychainError.accessDenied
Çözüm    : Keychain Access uygulamasından com.eliteagent için
           EliteAgent.app'e izin ver
```

### 22.7 Cloud Maliyet Limiti Aşıldı

```
Belirti  : [WARN] DAILY_COST_LIMIT; cloud çağrısı engellendi
Kontrol  : cost_ledger.json → bugünkü toplam
Çözüm    : Gece sıfırlanır; vault.plist'te maxDailyCostUSD artır
```

---

## 23. Ajan-Araç Yetki Matrisi

> Bu madde tek referans noktasıdır. Çelişki durumunda bu tablo geçerlidir.

| Araç / Kaynak | Orchestrator | Planner | Executor | Critic | Memory | Guard |
|---|:---:|:---:|:---:|:---:|:---:|:---:|
| **Tool Engine** | | | | | | |
| `read_file` | ✗ | ✗ | ✅ | ✗ | ✅ (L2) | ✗ |
| `write_file` | ✗ | ✗ | ✅ + onay | ✗ | ✅ (L2) | ✗ |
| `list_dir` | ✗ | ✗ | ✅ | ✗ | ✗ | ✗ |
| `delete_file` | ✗ | ✗ | ✅ + XPC + onay | ✗ | ✗ | ✗ |
| `shell` | ✗ | ✗ | ✅ + XPC + onay | ✗ | ✗ | ✗ |
| `web_search` | ✗ | ✗ | ✅ | ✗ | ✗ | ✗ |
| `web_fetch` | ✗ | ✗ | ✅ | ✗ | ✗ | ✗ |
| `json_parse` | ✗ | ✗ | ✅ | ✅ | ✗ | ✗ |
| `grep` | ✗ | ✗ | ✅ | ✅ | ✅ | ✗ |
| `summarize` | ✗ | ✗ | ✅ | ✅ | ✅ | ✗ |
| `desensitize` | ✗ | ✗ | ✗ | ✗ | ✗ | **✅ tek yetkili** |
| **MCP Gateway** | | | | | | |
| `mcp_call` | ✗ | ✗ | ✅ + onay | ✗ | ✗ | ✗ |
| **BrowserAgent** | | | | | | |
| `browser_navigate` | ✗ | ✗ | ✅ + onay | ✗ | ✗ | ✗ |
| `browser_read` | ✗ | ✗ | ✅ | ✗ | ✗ | ✗ |
| `browser_query` | ✗ | ✗ | ✅ | ✗ | ✗ | ✗ |
| `browser_fill` | ✗ | ✗ | ✅ + onay | ✗ | ✗ | ✗ |
| `browser_js` | ✗ | ✗ | ✅ + **her zaman onay** | ✗ | ✗ | ✗ |
| **CUA** | | | | | | |
| `cua_action` (screenshot, tree) | ✗ | ✗ | ✅ | ✗ | ✗ | ✗ |
| `cua_action` (click, scroll, key) | ✗ | ✗ | ✅ + onay | ✗ | ✗ | ✗ |
| `cua_action` (type) | ✗ | ✗ | ✅ + **her zaman onay** | ✗ | ✗ | ✗ |
| **Sistem** | | | | | | |
| L1 Actor state (doğrudan) | ✗ | ✗ | ✗ | ✗ | ✅ | ✗ |
| MEMORY_WRITE / READ sinyal | ✅ | ✅ | ✅ | ✅ | — | ✅ |
| PRIVACY_CHECK sinyal emit | ✅ | ✗ | ✗ | ✗ | ✅ | — |
| Privacy karar emit | — | — | — | — | — | ✅ |
| audit.log yazma | ✅ | ✗ | ✅ | ✗ | ✅ | ✅ |
| security.log yazma | ✅ | ✗ | ✗ | ✗ | ✗ | ✅ |
| **LLM** | | | | | | |
| MLX / Ollama (local) | ✗ | ✅ | ✅ | ✅ | ✗ | ✅ |
| Cloud API | ✗ | ✅ | ✅ | ✅ | ✗ | **✗ hardcode yasak** |
| **Git** | | | | | | |
| GIT_COMMIT emit | ✗ | ✗ | ✗ | ✗ | ✅ | ✗ |
| GIT_REVERT emit | ✅ (kullanıcı onaylı) | ✗ | ✗ | ✗ | ✗ | ✗ |
| **Bellek Dosyaları** | | | | | | |
| KNOWLEDGE_BASE-FULL.md okuma | ✗ | ✅ (local routing) | ✗ | ✗ | ✅ | ✅ |
| KNOWLEDGE_BASE-FULL.md yazma | ✗ | ✗ | ✗ | ✗ | ✅ | ✗ |
| KNOWLEDGE_BASE.md okuma | ✗ | ✅ | ✗ | ✗ | ✅ | ✗ |
| KNOWLEDGE_BASE.md yazma | ✗ | ✗ | ✗ | ✗ | ✅ | ✗ |

### 23.1 Kural Hiyerarşisi

```
1. Bu tablo (Madde 23)              — en yüksek öncelik
2. Privacy Guard kuralları (Madde 7) — ikinci öncelik
3. Güvenlik kuralları (Madde 18)    — üçüncü öncelik
4. Tool tanımları (Madde 10)        — dördüncü öncelik
5. vault.plist konfigürasyonu       — en düşük öncelik
```

**vault.plist'ten değiştirilemez hardcode kurallar:**
- Guard cloud provider kullanamaz
- `desensitize` yalnızca Guard kullanabilir
- `type` CUA aksiyonu her zaman onay gerektirir
- L1 Actor state doğrudan erişimi yalnızca Memory Actor
- security.log yazma yalnızca Orchestrator ve Guard

### 23.2 Yetki İhlali

```swift
// Erişim reddedilir
throw AgentError.accessDenied(agent: agentID, resource: toolID)
// → Orchestrator → SECURITY_FLAG
// → security.log: [ISO] [SECURITY] ACCESS_DENIED agent=X resource=Y
// → 3 ardışık → AGENT_ISOLATION
```

---

## 24. Gelecek Vizyon

> Bu maddedeki hiçbir özellik bu doküman güncellenmeden ve tetikleyici koşullar oluşmadan implemente edilemez.

### 24.1 Vizyon Aşaması 4 — The Cortex

**Ön koşul:** Madde 21 takvimindeki tüm 70 özellik `ACCEPTED`.

**Heartbeat:** 30 dakikada bir `HEARTBEAT.md` okunur; `## PENDING:` görevler çalıştırılır. Heartbeat modunda `shell` ve `mcp_call` çalışmaz. Guard Privacy Check zorunludur.

**MLX Model Yönetimi:** Yeni MLX modeller arka planda indirilir; eski modeller otomatik temizlenir. Model kalite karşılaştırması (Critic puanlama ile benchmark).

**Spotlight Entegrasyonu:** `NSUserActivity` ile Elite Agent görevleri Spotlight'ta aranabilir hale gelir.

**Persistent Session:** Her açılışta önceki oturumun bağlamı yüklenir.

**Dinamik Skill Keşfi:** Sistemde kurulu araçlar (ffmpeg, imagemagick) tespit edilir; `tools/` dizinine tanım eklenir.

**Apple Shortcuts Entegrasyonu:** `INIntent` ile Shortcuts'tan doğrudan Elite Agent görevi tetiklenebilir.

### 24.2 Vizyon Aşaması 5 — The Network

**Ön koşul:** Vizyon Aşaması 4 stabil.

**A2A Protokolü:** Google/Linux Foundation A2A ile diğer ajanlara görev devretme. Gelen payload Guard'dan geçer; `approvalThreshold: 1`.

**iOS Companion:** Elite Agent daemon'una uzaktan bağlanan, iPhone/iPad üzerinden görev başlatma imkânı sunan basit iOS uygulaması. (Core daemon macOS'ta kalır.)

**iCloud Hafıza Senkronizasyonu:** KNOWLEDGE_BASE.md (cloud-safe) iCloud Drive'a otomatik yedek. KNOWLEDGE_BASE-FULL.md hiçbir koşulda iCloud'a gitmez.

### 24.3 Kapalı Kararlar

| Karar | Gerekçe |
|-------|---------|
| Node.js runtime | Elite Agent safkan Swift; bu karar kalıcıdır |
| Electron / web tabanlı UI | macOS native citizen olmaz |
| LangChain, LlamaIndex | Antigravity ihlali |
| Harici PII kütüphanesi | Regex + MLX yeterli |
| Docker / WASM sandbox | XPC native ve daha güçlü |
| Heartbeat'te shell/mcp_call | Güvenlik riski; kullanıcısız ortamda kabul edilemez |
| KNOWLEDGE_BASE-FULL iCloud sync | Privacy ihlali |

---

### Madde 25 — Auth & Monetizasyon Katmanı 

**Auth: Sign In with Apple (ASAuthorizationController)
      Apple ID token → Supabase Auth
      
**Kullanıcı verisi (Supabase):
  users         → apple_user_id, email, created_at, plan
  subscriptions → plan (free/premium), status, expires_at
  usage_quotas  → daily_tasks, monthly_cost_usd, reset_at
  devices       → device_id, mac_model, last_seen

**Local'de kalan veriler (değişmez):
  Görevler, dosyalar, KNOWLEDGE_BASE, PII — Supabase'e gitmiyor

**Monetizasyon: StoreKit 2
  Free tier  → günlük 10 görev, cloud-only profil
  Premium    → sınırsız görev, tüm profiller, MLX, BrowserAgent
  Fiyat: aylık/yıllık (App Store'da belirlenir)
  
  
---

*Bu doküman Antigravity prensiplerine ve Apple Silicon native mimari kararına göre oluşturulmuştur.*
*Elite Agent Core · v5.2-elite · 21 Mart 2026*
