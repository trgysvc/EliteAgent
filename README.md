# 🛸 EliteAgent

<p align="center">
  <b>A fully autonomous and hardware-aware Hybrid Intelligence Agent running on your desktop.</b><br>
  <i>Powered by the <b>UNO (Unified Native Orchestration)</b> architecture, featuring distributed actors and Apple Silicon optimization.</i>
</p>

---

## 📖 About the Project
**EliteAgent** is an advanced native macOS application rather than a standard LLM (Large Language Model) text client. It is a **Hybrid Intelligence** tool capable of training its own subagents, executing terminal commands, navigating the web, and performing "Graceful Degradation" based on your system's hardware telemetry.

EliteAgent combines the analytical prowess of frontier cloud models (e.g., via OpenRouter) with the speed and privacy of local SLMs (Small Language Models) running natively on Apple M-Series GPUs and NPUs.

> **[v19.7.1 UNO Pure]**: Zero-JSON Binary-Native Architecture, Resilient Optional-Cloud, and Hardened Core Orchestration.

## 🔥 Key Features

### 1. Self-Healing & Architecture Hardening [v15.0 OFFICIAL SEAL]
- **Eco-Inference Mode [v19.0]:** Thermal-aware dynamic throttling that injects nanosecond delays (5ms-200ms) in the token loop based on `thermalState` to prevent hardware degradation.
- **Structural Isolation (Structural Security):** Separates system instructions from untrusted external data (Files, Web) to prevent prompt injection.
- **Official Iron Seal Build:** 100% compliant with Apple Distributed Actor standards and Swift 6 ownership transfer (SE-0430).
- **YOLO Guard v2 & Encrypted Audits:** Dynamic risk assessment with Keychain-backed AES.GCM forensic logging.
- **XPC Architecture Hardening [v13.7]:** Deterministic C-module resolution (`yyjson`, `Cmlx`, `_NumericsShims`) with absolute path enforcement.

### 2. Autonomous Recursive Evolution [v18.0 RECURSIVE]
- **PluginCraft Engine:** The system can now generate, compile (`swiftc`), ad-hoc sign (`codesign`), and dynamically load (`dlopen`) its own tools at runtime.
- **Zero-Dependency Plugin Build:** Standalone `PluginInterface` allows instant tool compilation without linking complex external dependencies.
- **Dynamic Serial Queue:** FIFO task management prevents state contamination and ensures sequential integrity.
- **Pure UNO Architecture [v19.5]:** Zero-JSON binary-native orchestration. All structural control is handled via `[UNOB: ...]` binary tags, eliminating parsing hallucinations and infinite loops.
- **Legacy Bridge Purge:** Complete removal of Ollama (Port 11434) and third-party bridge dependencies. 100% self-contained local inference.
- **Biometric Guard:** Secured WhatsApp/iMessage communication with mandatory TouchID/Apple ID verification.

### 3. Purpose Lock & Context Isolation [v14.5 - CORE]
- **Strict Context Isolation:** Each task in the queue starts with a "Tabula Rasa" (clean page), preventing previous errors from leaking into new prompts.
- **Intent Persistence:** Mission-bound intelligence that prevents task-switching during failures.
- **Disciplinary Classification:** Hardened intent mapping ensures high-priority tasks are isolated from general chat context.

### 4. Apple-Native Standards & Data Protection [v14.0 - PRODUCTION]
- **Standard Directory Compliance:** Fully adheres to Apple's macOS FileSystem standards (`~/Library/Logs`, `~/Library/Application Support`).
- **Smart Data Preservation:** Factory reset logic explicitly excludes the `EliteAgentWorkspace`, ensuring user-generated work is never lost.
- **Persistent Model Safety:** LLM models are stored in non-volatile `Application Support` directories to prevent automatic system cache sweeps.

### 2. Titan Engine v3 (Intelligence & Diagnostics) - [v13.9 HARDENED]
- **Qwen 3.5 9B Specialization (4-bit):** Native **4-bit Quantized** Qwen 3.5 9B via `InferenceActor`, providing high-speed local reasoning.
- **Hallucination Protection Shield:** Integrated **1.4x Repetition Penalty** and token-loop detection for s-tier stability.
- **GGUF Integrity Shield:** Mandatory verification (Magic bytes, Version v3+, and Tensors) to prevent memory corruption.
- **Unified Memory Diagnostics:** Fully Sandbox-compliant memory management using heuristics and `ProcessInfo`.

### 3. M-Series Mastery & ANE Offloading [v19.0 NEW]
- **ANE-Offloading (CoreML Bridge):** Routine tasks (intent classification, embeddings) are offloaded to the **Apple Neural Engine (ANE)**, freeing the GPU for primary LLM inference.
- **Eco-Inference Throttling:** Real-time monitoring of `ProcessInfo.thermalState` to intelligently manage duty cycles on fanless models like MacBook Air.
- **Zero-Copy Architecture:** Unified memory optimization ensuring no data duplication between MLX (GPU) and CoreML (ANE) buffers.
- **XcodeEngine:** Direct management of Swift/Xcode projects including mapping, building, and self-healing build errors.
- **SourceKit-LSP Native Bridge:** Deep semantic code understanding, navigation, and diagnostics for accurate codebase modification.

### 4. Audio Intelligence & Music DNA (Librosa Killer) - [v7.1]
- **Chroma CENS (Energy Normalized Statistics):** Native implementation of the Librosa `chroma_cens` algorithm for superior cover-song and harmonic fingerprinting.
- **Multi-Band PLP (Predominant Local Pulse):** Advanced rhythm tracking using frequency-band splitting (**Sub, Low, Mid, High**). 
- **Hardware-Native DSP:** All spectral analysis (STFT, Mel, CQT, YIN, Chroma, PLP) is vectorized via the **Accelerate** (vDSP) framework.

### 3. Production-Ready File Engine (DocEye v2)
- **Memory-Safe Ingestion:** Supports 50MB+ documents using **Memory-Mapped I/O** (`mappedIfSafe`), ensuring stable performance on 8GB-16GB RAM hardware.
- **Deterministic Cleanup:** Implementation of a secure lifecycle for model weights, using a 50ms grace period to release **mmap locks** before deletion or switching.

### 4. Hardware Protection Shield (Hardware Reflex)
- **System Watchdog:** The agent continuously communicates with your hardware. It tracks `ProcessInfo.thermalState` and `MemoryPressure` every second.
- **PVP (Production Verification Protocol) [NEW]:** A comprehensive CLI verification suite (`swift run elite --verify-pvp`) that stress-tests memory pressure handling, fallback logic, and integrity shields.

### 5. Research Intelligence Mode [v9.9]
- **Silent Multi-Source Scraping:** Background research using headless `WKWebView` (No Safari tabs opened).
- **Ultra-Resilient Parsing:** `ThinkParser` with 3-level JSON extraction (Direct/CodeBlock/Regex Fallback).
- **Autonomous JSON Detection:** Intercepts structured LLM payloads to trigger premium `ResearchReportView` UI.
- **Multi-Tool Chain Support [v9.9.3]:** Upgraded `ThinkParser` extracts and executes multiple `tool_code` blocks in a single turn, even without backticks.
- **Summarization Fallback:** Auto-titling sessions now falls back to local Titan models if cloud API keys are missing.
- **KAIROS Adaptive Heartbeat (v10.0):** Proactive energy management (15s-120s heartbeat) based on thermal and battery state.
- **Dream Engine v2 (Autonomous Memory) [v10.0]**:
    - **Background Consolidation**: L1 bağlamını `memory_v{N}.md` dosyalarına otonom olarak özetleyen `DreamActor`.
    - **Net-Savings Validation**: Özet boyutu ham verinin %25'inden fazlaysa işlemi iptal eden verimlilik kalkanı.
    - **Diff-Based Sync**: Bellek güncellemelerinde sadece değişen kısımları (`diff.log`) takip eden hafif mimari.
- **Prompt Cache Manager (SHA256) [v10.0]**: 
    - **KV-Cache Optimization**: Statik sistem komutlarını dinamik veriden ayırarak Apple Silicon KV-cache verimini %80 artıran otonom yönlendirici.
    - **Adaptive Prefix Shrinking**: Hit oranı %60'ın altına düştüğünde prefix boyutunu küçülterek başarılı cache ihtimalini artıran otonom refleks.
- **Token Guard Suite [v10.0 New Features]**:
    - **TokenAccountant Middleware**: Input, Output ve Cache token'larını anlık raporlayan `actor` tabanlı takip sistemi.
    - **OutputSchemaGuard (Brief Mode)**: Yanıt boyutunu girdiyle oranlayarak (%60) semantik olarak sınırlayan çıktı kalkanı.
    - **Prompt Cache Monitor**: `os_signpost` ile yerel performans izleme ve verimlilik analitiği.
    - **token_baselines.json**: CI/CD süreçleri için senaryo bazlı token verimlilik hedefleri ve regresyon takibi.
- **Universal Shortcuts Bridge [NEW]:** Native integration with macOS Shortcuts (`shortcuts list`, `shortcuts run`) with 1-hour caching and stdin support.

### 6. Universal Tool Ecosystem
- **MessengerTool (Autonomous WhatsApp/iMessage):** Biometric-secured communication with localized error handling and Multi-Step synchronization.
- **PatchTool & WriteFileTool:** Atomic string-matching (diff) for safe codebase modification.
- **Brave Search & Web Fetch:** Deep-web scouring via Brave API with Markdown structure preservation.
- **Chicago Vision (v10.0):** Native screen analysis via `ScreenCaptureKit` and `VNRecognizeTextRequest` (macOS 15+).
- **AX Automation (v10.0):** Direct application interaction via `AXUIElement` with AppleScript fallback.
- **Tulpar (Mythology Buddy) [v10.0]:** Zero-latency ASCII companion for real-time state visualization.
- **Experience Vault (MemoryTool):** L2 vector database for long-term algorithmic memory.

### 7. Token Efficiency & Guard Suite [v10.0 NEW]
- **TokenAccountant Middleware:** Real-time billing and KV-cache hit tracking (Input/Output/Cached).
- **OutputSchemaGuard (Brief Mode):** Enforces 60% compression with semantic sentence-level truncation.
- **Dream Net-Savings Validation:** Automated skip of memory consolidation if efficiency criteria ($\le 25\%$) are not met.
- **Adaptive Cache Scaling:** Proactive prefix shrinking when hit rates drop below 60% to recover performance.
- **CI/CD Token Regression:** Build-time verification against `token_baselines.json` with 20% failure threshold.

### 6. macOS Native Architecture (HIG Compliant)
- **Privacy Manifest (2024):** Fully compliant `PrivacyInfo.xcprivacy` for File Timestamp, Disk Space, and Apple Events usage.
- **Standard Path Management:** strictly follows HIG for `Application Support`, `Caches`, and `Logs`.
- **Memory-Efficient Integrity:** Uses **Chunked SHA-256** (64MB blocks) to verify multi-gigabyte model weights.

---

## ⚙️ Installation & Build

EliteAgent is compiled strictly using Apple's most modern concurrency standards (`Swift 6`, `@MainActor`, `Sendable`).

### Requirements
- **Operating System:** macOS 15.0 or later.
- **Processor:** Apple Silicon (M1/M2/M3/M4, etc.).
- **Memory:** 16GB RAM minimum recommended.
- **Development Environment:** Xcode 16.0 or later.

---

## 📂 Project Architecture

```
EliteAgent/
├── App/                       # Xcode SwiftUI Interface
├── Sources/
│   ├── elite/                 # PVP CLI Tool & Verification Suite
│   └── EliteAgentCore/        # The Core Brain
│       ├── Plugins/           # PluginCraft & Dynamic Registries
│       ├── XcodeEngine/       # XcodeTool & SourceKit-LSP Bridge
│       ├── Agents/            # Orchestrator, Planner, Critic
│       ├── ToolEngine/        # Messenger, Patch, Shell, Fetch
│       ├── UI/                # MTKView, NeuralSight.metal
│       ├── LLM/               # InferenceActor, HealthMonitor, Bridge
│       └── Security/          # VaultManager, Structural Isolation
├── Resources/                 # PluginInterface & App Assets
└── Package.swift              # SPM Modulations (MLX, Sparkle, etc.)
```

---

> *"Privacy by Design. Autonomy by Nature. Forensic by Intent. Native by Choice. Evolution by Recursive Logic. Hardware by Mastery. Pure by Architecture."*  
> **[EliteAgent Core - v19.7.1 UNO Pure - OFFICIAL IRON SEALED]**
