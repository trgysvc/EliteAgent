<div align="center">

# 🛸 ELITE AGENT

### The autonomous AI agent native to Apple Silicon

**macOS Only · Swift 6 · Apple Silicon M-series**

[![Status](https://img.shields.io/badge/status-in%20development-yellow)](https://github.com/eliteagent)
[![Platform](https://img.shields.io/badge/platform-macOS%2014%2B-blue)](https://github.com/eliteagent)
[![Swift](https://img.shields.io/badge/swift-6.0-orange)](https://swift.org)
[![License](https://img.shields.io/badge/license-MIT-green)](LICENSE)

*[English](#english) · [Türkçe](#türkçe)*

</div>

---

<a name="english"></a>

## 🇬🇧 English

### What is Elite Agent?

Elite Agent is a general-purpose autonomous agent that runs natively on Apple Silicon Macs. It thinks with local LLMs (via MLX) or cloud APIs (OpenRouter, Claude, GPT), controls any macOS application through Apple's Accessibility API, and keeps your private data from ever reaching the cloud.

It is not a wrapper. It is not Electron. It is a real macOS application — a launchd daemon with a SwiftUI interface, built entirely in Swift 6 with zero external dependencies beyond Apple's own frameworks and MLX.

---

### Why Elite Agent?

| | OpenClaw / Others | Elite Agent |
|---|---|---|
| **Platform** | Linux / Windows / Electron | macOS native — Swift 6 |
| **Local inference** | Cloud-first | MLX on Apple Silicon — R1, Llama, Qwen |
| **App control** | Chrome / terminal only | **Any macOS app** via AXUIElement |
| **Privacy** | Data leaves your machine | Guard layer — PII never reaches cloud |
| **Memory** | Session-only | Persistent L1/L2 + Git-backed state |
| **Sandbox** | Script-level | XPC Services — Apple native isolation |

---

### What Can It Do?

**Research & Writing**
Web search, page reading, summarization, multi-source comparison, report generation.

**Code & Development**
Write, refactor, test and debug Swift code. Build and run Xcode projects via Xcode MCP. Integrate Figma components directly into your Xcode workspace.

**File & System Operations**
Read, write, organize files. Run terminal commands in XPC-isolated sandbox. Grep, parse JSON, transform data.

**macOS App Automation (CUA)**
Control any macOS application — Xcode, Finder, Safari, Slack, Adobe apps, Microsoft Office — through Apple's Accessibility tree. No browser extension. No Playwright. Native.

**Multi-step Workflows**
Chain any combination of the above. Planner decomposes the task, Executor runs it, Critic verifies the result. Self-correction on failure, human escalation after 3 retries.

---

### Usage Profiles

Elite Agent adapts to your hardware and preference:

**🖥 Local-First**
Uses MLX models running directly on your Mac's Unified Memory. Your data never leaves your machine. Best for privacy-sensitive work.
→ Requires 16 GB+ Unified Memory (96 GB+ for R1-32B)

**☁️ Cloud-Only**
No local model required. Uses OpenRouter, Claude, GPT-4o or any OpenAI-compatible API. Works on any Apple Silicon Mac, including 8 GB models.
→ Requires only an API key

**⚡️ Hybrid**
Small/fast tasks → local 8B model. Complex/critical tasks → cloud. Best balance of speed, cost and privacy.
→ Requires 16 GB Unified Memory

---

### Hardware Requirements

| Chip | Memory | Recommended Profile | Local Model |
|------|--------|---------------------|-------------|
| M1 / M2 | 8 GB | Cloud-Only | — |
| M1 / M2 | 16 GB | Hybrid | Llama-3-8B |
| M2 Pro/Max | 32–96 GB | Local-First | R1-8B / R1-32B (96 GB+) |
| M3 Pro/Max | 36–128 GB | Local-First | R1-8B / R1-32B (128 GB) |
| M4 Pro/Max | 24–128 GB | Local-First | R1-8B / R1-32B (128 GB) |

> **Note:** R1-32B has been observed to consume ~120 GB in real use. On systems with less, Dynamic Downscaling automatically switches to a smaller model under memory pressure.

---

### Supported LLM Providers

| Provider | Type | Notes |
|----------|------|-------|
| MLX (DeepSeek R1-32B / 8B) | Local | Native M-series inference; fastest |
| MLX (Llama-3-8B, Qwen-2.5-Coder) | Local | Executor and Critic agents |
| Ollama (Metal acceleration) | Local | Fallback when MLX format unavailable |
| [OpenRouter](https://openrouter.ai) | Cloud | 200+ models; single API key |
| Anthropic Claude | Cloud | Direct API |
| OpenAI GPT-4o / mini | Cloud | Direct API |
| Any OpenAI-compatible API | Cloud | Groq, Mistral, vLLM, LM Studio |

---

### Privacy Guard

Every piece of content heading to the cloud passes through the Guard layer first:

```
Content → Rule check (regex, <10ms) → Model check (local R1-8B, <3s)
                                              ↓
                         PASS          DESENSITIZE          BLOCK
                           ↓                ↓                  ↓
                      send to cloud    mask PII, send     local only
```

Guard never uses cloud models. Its decisions are themselves sensitive information.

Turkish ID numbers, IBANs, phone numbers, emails and coordinates are masked automatically before any cloud call. Original data stays in `KNOWLEDGE_BASE-FULL.md` — local only.

---

### Agent Architecture

Five Swift Actors running in parallel, orchestrated by a `@MainActor` Orchestrator:

```
Orchestrator (@MainActor)
├── Planner    — strategy, task decomposition, tool selection
├── Executor   — runs tools, MCP calls, CUA actions
├── Critic     — quality check, self-correction (0-10 score)
├── Memory     — L1 cache + L2 disk, retrieval, Git commits
└── Guard      — privacy decisions (cloud access: NEVER)
```

Every action is committed to Git. Wrong result? `git revert` in seconds.

---

### For Developers

**Tech Stack**
- Swift 6 (strict concurrency, Actor model)
- SwiftUI + AppKit (Menu Bar, Chat Window)
- MLX Swift (local inference on M-series)
- XPC Services (shell sandbox)
- AXUIElement (macOS app control)
- Foundation Process (Git operations)
- URLSession (all network calls)
- Keychain (secrets storage — never in plaintext)
- launchd (system daemon)

**No external dependencies** beyond `mlx-swift` and `mlx-swift-examples` from Apple's ML Explore org.

**Project Structure**
```
EliteAgent.xcodeproj
├── Sources/
│   ├── App/              SwiftUI interface, Menu Bar
│   ├── Core/
│   │   ├── Agents/       Planner, Executor, Critic, Memory, Guard
│   │   ├── Bridge/       Harpsichord Bridge, MLX/Ollama/Cloud providers
│   │   ├── Tools/        Tool Engine (filesystem, web, data)
│   │   ├── MCP/          MCP Gateway (Xcode, Figma, Chrome)
│   │   ├── Memory/       L1 cache, L2 storage, Git State Engine
│   │   ├── CUA/          AXUIElement bridge
│   │   ├── Privacy/      Rule-based + model-based Guard
│   │   └── Security/     HMAC signing, Prompt sanitizer, Keychain
│   └── XPCService/       Isolated shell execution
├── Tests/
└── Installer/            .pkg builder, launchd plist
```

**Configuration**
All settings live in `~/.eliteagent/vault.plist`. API keys are stored in macOS Keychain — never in the plist file.

```xml
<key>routing</key>
<dict>
  <!-- local_first | cloud_only | hybrid -->
  <key>strategy</key><string>local_first</string>
  <key>maxDailyCostUSD</key><real>5.0</real>
</dict>
```

**PRD**
Full architecture specification: [`EliteAgent_PRD_v5.2.md`](EliteAgent_PRD_v5.2.md)

---

### Development Status

> 🟡 **This project is in active development. No installable build is available yet.**

| Phase | Scope | Status |
|-------|-------|--------|
| Foundation | Actor skeleton, Signal system, Keychain, launchd | 🔲 In progress |
| LLM Bridge | MLX + Ollama + Cloud providers, routing profiles | 🔲 Planned |
| Tool Engine | File, shell (XPC), web search | 🔲 Planned |
| Privacy Guard | Rule + model check, cache, cloud-only mode | 🔲 Planned |
| Task Loop | Planner prompts, Critic scoring, self-correction | 🔲 Planned |
| Memory | L1/L2, retrieval, Git State Engine | 🔲 Planned |
| MCP Gateway | Xcode, Figma, Chrome | 🔲 Planned |
| CUA | AXUIElement, observe→decide→act loop | 🔲 Planned |
| UI | SwiftUI chat window, Menu Bar, Dashboard | 🔲 Planned |

---

### Contributing

Architecture decisions are documented in the PRD. Before opening a PR:
1. Check that the feature is defined in [`EliteAgent_PRD_v5.2.md`](EliteAgent_PRD_v5.2.md)
2. Undefined features require a PRD update first — then code

---

<a name="türkçe"></a>

## 🇹🇷 Türkçe

### Elite Agent Nedir?

Elite Agent, Apple Silicon Mac'lerde native olarak çalışan genel amaçlı otonom bir ajandır. Local LLM'ler (MLX aracılığıyla) veya cloud API'leri (OpenRouter, Claude, GPT) kullanarak düşünür; Apple'ın Erişilebilirlik API'si sayesinde her macOS uygulamasını kontrol edebilir; özel verilerinin buluta ulaşmasını önler.

Wrapper değil. Electron değil. Gerçek bir macOS uygulaması — SwiftUI arayüzüne sahip bir launchd daemon. Apple'ın kendi framework'leri ve MLX dışında sıfır harici bağımlılık; tamamı Swift 6 ile yazılmış.

---

### Neden Elite Agent?

| | OpenClaw / Diğerleri | Elite Agent |
|---|---|---|
| **Platform** | Linux / Windows / Electron | macOS native — Swift 6 |
| **Local inference** | Cloud öncelikli | Apple Silicon'da MLX — R1, Llama, Qwen |
| **Uygulama kontrolü** | Yalnızca Chrome / terminal | **Her macOS uygulaması** AXUIElement ile |
| **Gizlilik** | Veri makinenden çıkıyor | Guard katmanı — PII buluta gitmiyor |
| **Hafıza** | Yalnızca oturum içi | Kalıcı L1/L2 + Git tabanlı durum |
| **Sandbox** | Script seviyesi | XPC Services — Apple native izolasyon |

---

### Neler Yapabilir?

**Araştırma & Yazım**
Web araması, sayfa okuma, özetleme, çok kaynaklı karşılaştırma, rapor oluşturma.

**Kod & Geliştirme**
Swift kodu yazma, refactor, test ve debug. Xcode MCP ile Xcode projelerini build etme ve çalıştırma. Figma bileşenlerini doğrudan Xcode workspace'e entegre etme.

**Dosya & Sistem İşlemleri**
Dosya okuma, yazma, düzenleme. XPC izolasyonlu sandbox'ta terminal komutları çalıştırma. Grep, JSON parse, veri dönüştürme.

**macOS Uygulama Otomasyonu (CUA)**
Xcode, Finder, Safari, Slack, Adobe uygulamaları, Microsoft Office — Apple'ın Erişilebilirlik ağacı üzerinden herhangi bir macOS uygulamasını kontrol etme. Tarayıcı eklentisi yok. Playwright yok. Native.

**Çok Adımlı İş Akışı**
Yukarıdakilerin herhangi bir kombinasyonunu zincirle. Planner görevi parçalara ayırır, Executor çalıştırır, Critic sonucu doğrular. Hata durumunda self-correction, 3 denemede çözülemezse insan müdahalesi.

---

### Kullanım Profilleri

Elite Agent donanımına ve tercihine göre uyum sağlar:

**🖥 Local-First**
Mac'in Unified Memory'sinde doğrudan MLX modelleri kullanır. Veriler makinenden hiç çıkmaz. Gizlilik öncelikli işler için idealdir.
→ 16 GB+ Unified Memory gerektirir (R1-32B için 96 GB+)

**☁️ Cloud-Only**
Local model kurulumu gerekmez. OpenRouter, Claude, GPT-4o veya herhangi bir OpenAI-compat API kullanır. 8 GB'lık modeller dahil her Apple Silicon Mac'te çalışır.
→ Yalnızca bir API anahtarı gerektirir

**⚡️ Hibrit**
Küçük/hızlı görevler → local 8B model. Karmaşık/kritik görevler → cloud. Hız, maliyet ve gizlilik dengesi için en iyi seçim.
→ 16 GB Unified Memory gerektirir

---

### Donanım Gereksinimleri

| Chip | Bellek | Önerilen Profil | Local Model |
|------|--------|-----------------|-------------|
| M1 / M2 | 8 GB | Cloud-Only | — |
| M1 / M2 | 16 GB | Hibrit | Llama-3-8B |
| M2 Pro/Max | 32–96 GB | Local-First | R1-8B / R1-32B (96 GB+) |
| M3 Pro/Max | 36–128 GB | Local-First | R1-8B / R1-32B (128 GB) |
| M4 Pro/Max | 24–128 GB | Local-First | R1-8B / R1-32B (128 GB) |

> **Not:** R1-32B'nin gerçek kullanımda ~120 GB tükettiği gözlemlenmiştir. Daha düşük belleğe sahip sistemlerde Dynamic Downscaling, bellek baskısı altında otomatik olarak daha küçük bir modele geçer.

---

### Desteklenen LLM Sağlayıcıları

| Sağlayıcı | Tip | Notlar |
|-----------|-----|--------|
| MLX (DeepSeek R1-32B / 8B) | Local | M serisi native; en hızlı |
| MLX (Llama-3-8B, Qwen-2.5-Coder) | Local | Executor ve Critic ajanları |
| Ollama (Metal hızlandırma) | Local | MLX formatı yoksa fallback |
| [OpenRouter](https://openrouter.ai) | Cloud | 200+ model; tek API anahtarı |
| Anthropic Claude | Cloud | Direkt API |
| OpenAI GPT-4o / mini | Cloud | Direkt API |
| OpenAI-compat herhangi bir API | Cloud | Groq, Mistral, vLLM, LM Studio |

---

### Privacy Guard

Buluta gidecek her içerik önce Guard katmanından geçer:

```
İçerik → Kural kontrolü (regex, <10ms) → Model kontrolü (local R1-8B, <3s)
                                                    ↓
                           PASS            DESENSITIZE          BLOCK
                             ↓                  ↓                  ↓
                        buluta gönder     PII maskele, gönder  yalnızca local
```

Guard hiçbir zaman cloud model kullanmaz. Kararlarının kendisi hassas bilgidir.

TC kimlik numaraları, IBAN'lar, telefon numaraları, e-postalar ve koordinatlar herhangi bir cloud çağrısından önce otomatik olarak maskelenir. Orijinal veri yalnızca `KNOWLEDGE_BASE-FULL.md`'de — lokaldir.

---

### Ajan Mimarisi

Bir `@MainActor` Orchestrator tarafından yönetilen, paralel çalışan beş Swift Actor:

```
Orchestrator (@MainActor)
├── Planner    — strateji, görev decomposition, araç seçimi
├── Executor   — araçları çalıştırır, MCP çağrıları, CUA aksiyonları
├── Critic     — kalite denetimi, self-correction (0-10 puan)
├── Memory     — L1 cache + L2 disk, retrieval, Git commit'leri
└── Guard      — gizlilik kararları (cloud erişimi: ASLA)
```

Her aksiyon Git'e commit'lenir. Yanlış sonuç? Saniyeler içinde `git revert`.

---

### Geliştiriciler İçin

**Teknoloji Stack'i**
- Swift 6 (strict concurrency, Actor modeli)
- SwiftUI + AppKit (Menu Bar, Chat Penceresi)
- MLX Swift (M serisi üzerinde local inference)
- XPC Services (shell sandbox)
- AXUIElement (macOS uygulama kontrolü)
- Foundation Process (Git işlemleri)
- URLSession (tüm ağ çağrıları)
- Keychain (secret yönetimi — düz metin asla)
- launchd (sistem daemon'u)

Apple'ın ML Explore org'undan `mlx-swift` ve `mlx-swift-examples` dışında **harici bağımlılık yok**.

**Konfigürasyon**
Tüm ayarlar `~/.eliteagent/vault.plist`'te tutulur. API anahtarları macOS Keychain'de saklanır — plist dosyasında asla.

```xml
<key>routing</key>
<dict>
  <!-- local_first | cloud_only | hybrid -->
  <key>strategy</key><string>local_first</string>
  <key>maxDailyCostUSD</key><real>5.0</real>
</dict>
```

**PRD (Teknik Mimari Dokümanı)**
Tam mimari spesifikasyon: [`EliteAgent_PRD_v5.2.md`](EliteAgent_PRD_v5.2.md)

---

### Geliştirme Durumu

> 🟡 **Bu proje aktif geliştirme aşamasındadır. Henüz kurulabilir bir build mevcut değildir.**

| Aşama | Kapsam | Durum |
|-------|--------|-------|
| Temel Altyapı | Actor iskeleti, Sinyal sistemi, Keychain, launchd | 🔲 Devam ediyor |
| LLM Bridge | MLX + Ollama + Cloud, routing profilleri | 🔲 Planlandı |
| Tool Engine | Dosya, shell (XPC), web araması | 🔲 Planlandı |
| Privacy Guard | Kural + model kontrolü, cache, cloud-only mod | 🔲 Planlandı |
| Görev Döngüsü | Planner şablonları, Critic puanlama, self-correction | 🔲 Planlandı |
| Hafıza | L1/L2, retrieval, Git State Engine | 🔲 Planlandı |
| MCP Gateway | Xcode, Figma, Chrome | 🔲 Planlandı |
| CUA | AXUIElement, observe→decide→act döngüsü | 🔲 Planlandı |
| Arayüz | SwiftUI chat penceresi, Menu Bar, Dashboard | 🔲 Planlandı |

---

### Katkıda Bulunmak

Mimari kararlar PRD'de belgelenmiştir. PR açmadan önce:
1. Özelliğin [`EliteAgent_PRD_v5.2.md`](EliteAgent_PRD_v5.2.md)'de tanımlı olduğunu doğrula
2. Tanımsız özellikler önce PRD güncellemesi gerektirir — sonra kod

---

<div align="center">

*Elite Agent Core · v5.1-elite · 2026*
*Built for Apple Silicon. Privacy by architecture. Zero compromise.*

</div>
