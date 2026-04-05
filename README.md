# 🛸 EliteAgent

<p align="center">
  <b>A fully autonomous and hardware-aware Hybrid Intelligence Agent running on your desktop.</b><br>
  <i>An end-to-end intelligence bridge built specifically for Apple Silicon (M-Series), featuring the "Titan" architecture.</i>
</p>

---

## 📖 About the Project
**EliteAgent** is an advanced native macOS application rather than a standard LLM (Large Language Model) text client. It is a **Hybrid Intelligence** tool capable of training its own subagents, executing terminal commands, navigating the web, and performing "Graceful Degradation" based on your system's hardware telemetry.

EliteAgent combines the analytical prowess of frontier cloud models (e.g., via OpenRouter) with the speed and privacy of local SLMs (Small Language Models) running natively on Apple M-Series GPUs and NPUs.

## 🔥 Key Features

### 1. Self-Healing & Architecture Hardening [v9.9 STABILIZED]
- **Silent Background Research:** Elimination of Safari tab spam with headless `WKWebView` scraping—70% less resource usage.
- **Atomic State Management:** Centralized `ModelStateManager` for zero-latency Provider (Local/Cloud) synchronization.
- **Health Dashboard (Swift Charts):** Real-time monitoring of VRAM, TPS, and Thermal state with persistent history.
- **Stress Simulator:** Manual stress trigger to verify Auto-Recovery and Cloud Fallback mechanisms.
- **MLX Engine Guardian:** 180-second adaptive timeout and proactive VRAM sanitization.
- **Deep Recovery (Hard Reset):** Fast engine restart (2-3s) with session and memory preservation.

### 2. Titan Engine v3 (Intelligence & Diagnostics) - [v8.5 Production-Research]
- **Qwen 3.5 9B Specialization (4-bit):** Native **4-bit Quantized** Qwen 3.5 9B via `InferenceActor`, providing high-speed local reasoning.
- **GGUF Integrity Shield:** Mandatory verification (Magic bytes, Version v3+, and Tensors) to prevent memory corruption.
- **Unified Memory Diagnostics [HARDENED]:** Fully Sandbox-compliant memory management using heuristics and `ProcessInfo`, eliminating legacy Mach errors.
- **Advanced Diagnostics:** Detailed Hugging Face **401 (Gated)** and **404 (Not Found)** error detection.

### 2. Audio Intelligence & Music DNA (Librosa Killer) - [v7.1]
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
- **Real-Time Progress Feedback:** Live status indicators ("Analiz edilen kaynak: 3...") during deep research.

### 6. Universal Tool Ecosystem
- **MessengerTool (Autonomous WhatsApp/iMessage):** Production-hardened UI automation with localized error handling.
- **PatchTool & WriteFileTool:** Atomic string-matching (diff) for safe codebase modification.
- **Brave Search & Web Fetch:** Deep-web scouring via Brave API with Markdown structure preservation.
- **Image Analysis (Vision Analyzer):** Apple Vision OCR and coordinate extraction.
- **Experience Vault (MemoryTool):** L2 vector database for long-term algorithmic memory.

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
│       ├── Agents/            # Orchestrator, Planner, Critic
│       ├── ToolEngine/        # Messenger, Patch, Shell, Fetch
│       ├── UI/                # MTKView, NeuralSight.metal
│       ├── LLM/               # InferenceActor, HealthMonitor, Bridge
│       └── Security/          # VaultManager, PromptSanitizer
├── devlog.md                  # Comprehensive architectural history
└── Package.swift              # SPM Modulations (MLX, Sparkle, etc.)
```

---

> *"Privacy by Design. Autonomy by Nature. Forensic by Intent. Native by Choice."*  
> **[EliteAgent Core - v9.9 STABILIZED]**
