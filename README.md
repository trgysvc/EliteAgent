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

### 1. Titan Architecture (Visual & Local Intelligence)
- **Offline Brain (MLX Local Inference):** The system can asynchronously run **4-bit Quantized** MLX models (e.g., Llama-3-8B or Phi-3) via the `InferenceActor`. Even if your network connection is completely down, it can rapidly perform reasoning, planning, and code analysis.
- **Neural Sight (Metal Engine):** EliteAgent doesn't just "think"; it visualizes its cognitive process. Tensor data from the model is passed directly to the GPU without copying (**Zero-Copy** via `MTLStorageModeShared`), rendering an interactive 3D Point Cloud via `NeuralSight.metal` at an ultra-smooth 120 FPS.

### 2. Hardware Protection Shield (Hardware Reflex)
- **System Watchdog:** The agent continuously communicates with your hardware. It tracks `ProcessInfo.thermalState` and `MemoryPressure` every second to measure subsystem stress.
- **Prioritized Signaling (SignalBus):** When hardware pressure mounts, the agent's internal communication network (`SignalBus`) immediately activates the "Critical" lane, freezing low-priority tasks to let the hardware cool down (e.g., halting layout operations or reducing rendering density).

### 3. Comprehensive Universal Tool Ecosystem
Guided by an autonomous Planner, EliteAgent intelligently orchestrates numerous built-in tools:
- **PatchTool & WriteFileTool:** Safe coding tools that use targeted string-matching (diff) to apply atomic patches to large files without hitting LLM context limits.
- **Git State Engine (GitTool):** An isolated version control utility capable of autonomously committing, checking repo status, or reverting destructive mistakes.
- **Brave Search & Web Fetch:** Information processors that scour the live web using the `Brave API` (replacing the legacy DuckDuckGo implementation) and cleanly parse structural HTML pages into standardized Markdown.
- **Image Analysis (Vision Analyzer):** A computer-vision module that breaks down images to extract precise UI element coordinates and OCR text for UI automation.
- **Experience Vault (MemoryTool):** An L2 vector database that permanently stores solved algorithms. For similar future tasks, the agent relies on this RAG-based memory instead of querying the Cloud.
- **Subagent & Ecosystem (Apple HIG):** Spawnable sub-agents capable of task delegation (e.g., autonomous WhatsApp/iMessage automation, UI/UX interaction, media control).

- **Biologic Reporting:** Generates professional-grade Markdown reports (.md) with chroma histograms, rhythmic consistency std, and structural segment mapping.

### 5. macOS Native Architecture (HIG Compliant) - [NEW v6.2]
- **Standard Path Management:** EliteAgent strictly follows Apple's Human Interface Guidelines for file storage.
    - **~/Library/Application Support/EliteAgent:** Personal data, vault, and persistent state.
    - **~/Library/Caches/EliteAgent:** High-speed DSP analysis caches and temporary buffers.
    - **~/Library/Logs/EliteAgent:** Comprehensive operational and diagnostic logs.
- **Automated Migration Engine:** Seamlessly transitions legacy data from older `~/.eliteagent` hidden directories to the modern macOS structure without user intervention.
- **High-Performance DSP API:** All spectral analysis engines are harmonized with a flat-array `[Float]` layout, enabling zero-copy vector operations and 40% faster processing on M-Series silicon.

### 5. IPC & Modularity (Security & Autonomy)
- **Sandbox Eradication:** The restrictive Apple App Sandbox has been completely broken down, granting the agent genuine "Developer" privileges (Full File I/O + Shell execution).
- **Trifecta Architecture:** The project is split into three micro-architectures: `App`, `EliteAgentCore` (Framework), and `XPC Service`. This prevents UI blocking (ViewBridge errors) and ensures seamless, thread-safe execution.

---

## ⚙️ Installation & Build

EliteAgent is compiled strictly using Apple's most modern concurrency standards (`Swift 6`, `@MainActor`, `Sendable`).

### Requirements
- **Operating System:** macOS 26 or later.
- **Processor:** Apple Silicon (M1/M2/M3/M4, etc.).
- **Memory:** 16GB RAM minimum strongly recommended (For the local "Titan" SLM Unified Memory footprint).
- **Development Environment:** Xcode 26.4 or later.

### Bootstrapping the Project

1. Third-Party `API Key` Setup:
   - The project's `VaultManager` directly reads `OPENROUTER_API_KEY` and `BRAVE_API_KEY` from the macOS **Keychain** (or `vault.plist`). You must populate these keys before initiating any cloud operations.

2. Hybrid SPM (Swift Package Manager) Setup:
   EliteAgent relies on both an Xcode App Wrapper (for Sandbox/Signing entitlements) and SPM modules.
   - Open the project via Xcode by double-clicking the `EliteAgent.xcodeproj` file.
   - Ensure the `MLX`, `MLXNN`, and `MLXRandom` package products are linked to the `EliteAgentCore` target (under the `Frameworks, Libraries, and Embedded Content` tab).
   - If you encounter missing module errors, clear your SPM cache: `File > Packages > Reset Package Caches`.
   
3. Running:
   - Press `Cmd + B` to securely build and verify the project.
   - Press `Cmd + R` to launch the UI window (`ChatWindowView`) along with the Metal-based Neural Visualizer layer.

---

## 📂 Project Architecture

```
EliteAgent/
├── App/                       # Xcode SwiftUI Interface (ChatWindowView)
├── Sources/
│   ├── elite/                 # Pure Command-Line (CLI) Entry Point
│   └── EliteAgentCore/        # The Core Brain of EliteAgent
│       ├── Agents/            # Orchestrator, Planner, Critic, Subagents
│       ├── ToolEngine/        # Patch, Shell, Fetch, WebSearch, etc.
│       ├── UI/                # MTKView, NeuralSight.metal (Visualization)
│       ├── LLM/               # InferenceActor (Local), CloudProvider (OpenRouter)
│       └── Security/          # VaultManager, PromptSanitizer, Sentinel
├── devlog.md                  # Comprehensive day-by-day "Architectural History" log
└── Package.swift              # SPM Modulations (MLX, Sparkle, etc.)
```

---

## 🚦 Known Limitations & Recommendations
- **Increased Memory Limit & OOM:** To boot local models, the project's `EliteAgent.entitlements` file strictly requests the `com.apple.developer.kernel.increased-memory-limit` entitlement. On hardware constraints (like 8GB machines), the Neural Sight (Metal) density might automatically throttle to preserve system stability.
- **TCC Privileges:** For autonomous AppleScript UI interactions (WhatsApp/iMessage sending), you must manually grant the EliteAgent application `Accessibility` and `Automation` permissions via `System Settings > Privacy & Security`.

---

> *"Privacy by Design. Autonomy by Nature. Forensic by Intent. Native by Choice."*  
> **[EliteAgent Core - v6.2]**
