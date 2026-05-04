# 🛸 EliteAgent

<p align="center">
  <b>A fully autonomous and hardware-aware Hybrid Intelligence Agent running on your desktop.</b><br>
  <i>Powered by the <b>UNO (Unified Native Orchestration)</b> architecture — distributed actors, Apple Silicon optimization, zero JSON internally.</i>
</p>

---

## 🚀 Project Status: v8.1 "Titan Optimized" [ACTIVE]

EliteAgent is running on the **v3-Native Titan Engine** with full MLX-LM v3 integration, native tool calling (Qwen 3.5 xmlFunction format), and a complete performance optimization stack.

### v8.1 Achievements:
- **Native Tool Calling (Solution A):** Qwen 3.5 `<tool_call>` blocks parsed natively by mlx-swift-lm → `Generation.toolCall` → `OrchestratorRuntime` tool dispatch. Zero UBID translation required for native path.
- **Chat Latency Fix:** `enable_thinking: false` via `additionalContext` eliminates 800-token `<think>` blocks for chat intent. Response time: ~90s → <10s.
- **Wired Memory (Item 4):** `WiredMemoryUtils.tune()` measures real weight/KV/workspace bytes after model load. `WiredBudgetPolicy` pins weights in RAM during inference — lower first-token latency.
- **Rotating KV Cache (Item 5):** `maxKVSize = 8192` activates `RotatingKVCache`, preventing unbounded VRAM growth on long conversations.
- **KV Cache Quantization:** `kvBits=4, kvGroupSize=64, quantizedKVStart=256` → 50-75% KV memory reduction after 256 tokens.
- **Speculative Decoding (Item 6):** Infrastructure ready. Place a compatible draft model at `{mainModelURL}-draft` or call `InferenceActor.shared.loadDraftModel(at:)`. When loaded, uses `MLXLMCommon.generate(draftModel:numDraftTokens:4:)`.
- **Think Block Extraction:** `MLXProvider.extractThinkBlock()` splits raw model output into `(thinkContent, cleanResponse)` — UI never sees raw `<think>` tags.
- **System Prompt Fix:** `InferenceActor.generate()` now correctly prepends system messages (was silently ignored before v8.0).

---

## 🛠 Tool Inventory (v8.0 Master Registry)

EliteAgent features a precision-engineered suite of **38 native tools**, each identified by a Unique Binary ID (UBID) for zero-ambiguity model triggering.

| Category | Tools |
| :--- | :--- |
| **File Ops** | `file_manager`, `read_file`, `write_file`, `patch_file` |
| **System** | `shell_exec`, `volume_control`, `brightness_control`, `sleep_control`, `sys_info`, `telemetry`, `date_time` |
| **Web** | `web_search`, `web_fetch`, `safari_native`, `browser_scrape` |
| **Communication** | `whatsapp`, `messenger`, `email_send`, `mail_search` |
| **Media** | `media_control`, `music_dna`, `id3_editor` |
| **Imaging** | `image_analysis`, `chicago_vision` |
| **Development** | `git_action`, `xcode_engine` |
| **3D** | `blender_3d` |
| **Productivity** | `contacts`, `calendar`, `calculator`, `weather`, `timer`, `markdown_report`, `memory_vault` |
| **Discovery** | `app_discovery`, `shortcut_scan`, `shortcut_run`, `accessibility_ax`, `subagent_spawn` |

---

## 🏗 Architecture Highlights

EliteAgent is built on the **UNO (Unified Native Orchestration)** principle: *No JSON, No Middleware, No Lag.*

- **UNO Binary Protocol:** All inter-actor communication uses binary PropertyLists and memory-mapped buffers. JSON is strictly used at the external protocol boundary (HTTP layer) only, routed through `UNOExternalBridge`.
- **Titan Engine (InferenceActor):** MLX-powered local inference with wired memory pinning, rotating KV cache, 4-bit KV quantization, and optional speculative decoding.
- **Native Tool Calling:** Qwen 3.5 outputs `<tool_call>` blocks; mlx-swift-lm parses them to `Generation.toolCall`; `OrchestratorRuntime` dispatches via `ToolRegistry` name lookup.
- **Intent Classification:** Every user message is classified (chat vs. agent task) before routing. Chat → `enableThinking=false` (fast). Task → `enableThinking=true` (full reasoning).
- **Zero-Copy Memory (SharedMemoryPool):** Eliminates data copying between `InferenceActor` and `Orchestrator` via raw memory pointers across Actor boundaries.
- **Proactive UMA Watchdog:** Real-time hardware monitor that intelligently shrinks KV-caches or suspends non-critical tools when memory pressure exceeds 85%.
- **Native Safari Automation:** High-fidelity web control via `AXUIElement` and `SafariJSBridge`, bypassing heavy dependencies like Playwright.

---

## ⚙️ Getting Started

### Requirements
- **Hardware:** Apple Silicon (M1/M2/M3/M4 Series).
- **Memory:** 16GB RAM minimum (24GB+ recommended for Qwen 3.5 9B).
- **Software:** macOS 15.0+ (Sequoia), Xcode 16.1+, Swift 6.3.0.

### Installation
1. **Clone the Repository:**
   ```bash
   git clone https://github.com/trgysvc/EliteAgent.git
   ```
2. **Initialize Vault:**
   Create `~/Library/Application Support/EliteAgent/vault.plist` with your API keys (OpenRouter, etc.).
3. **Build & Run:**
   Open `EliteAgent.xcodeproj` in Xcode → select `EliteAgent` scheme → `Cmd+R`.

### Download a Model
Models live in `~/Library/Application Support/EliteAgent/Models/`. Recommended: `Qwen3.5-9B-OptiQ-4bit` from mlx-community.

To enable speculative decoding, place a compatible smaller model (same tokenizer family) at `Models/{mainModelName}-draft`.

### Permissions
Upon first run, EliteAgent requests:
- **Accessibility:** Required for `NativeBrowser` and `AccessibilityTool`.
- **Full Disk Access:** Recommended for `XcodeEngine` and `GitAction` stability.

---

## 📐 Architecture Rules (UNO)

| Rule | Detail |
|---|---|
| **No JSON internally** | Only `UNOExternalBridge.swift` may use `JSONEncoder`/`JSONDecoder`. All internal serialization uses binary PropertyList. |
| **No DispatchQueue** | All concurrency via `async/await`, `Task`, `actor`. Exception: FSEvents API (documented). |
| **No force unwrap** | `guard let` / `if let` / `as?` everywhere. |
| **UBID for tools** | Every tool has an `Int128` UBID registered in `ToolIDs.swift` before use. |
| **PathConfiguration** | Never hardcode paths. Use `PathConfiguration.shared.*URL`. |

---

## ⚖️ EliteAgent vs. OpenClaw

| Feature | OpenClaw | **EliteAgent (v8.1)** |
| :--- | :--- | :--- |
| **Platform** | Cross-platform (Python) | **macOS-Native (Swift 6)** |
| **Concurrency** | Threads/Processes | **Distributed Actors** |
| **Browser** | Playwright (Chrome) | **Native Safari (AX + JSBridge)** |
| **Memory** | Vector DB (Disk) | **Proactive UMA + Wired Memory** |
| **IPC** | JSON-RPC (String) | **UNO Binary (Zero-Copy Pointer)** |
| **Inference** | OpenAI API | **Local MLX (Titan Engine)** |
| **Tool Calling** | OpenAI format | **Native xmlFunction (Qwen 3.5)** |
| **KV Cache** | None | **4-bit Quant + Rotating (8K window)** |
| **Speculative** | None | **Draft model auto-load** |

---

> *"Privacy by Design. Autonomy by Nature. Forensic by Intent. Native by Choice. Hardware by Mastery. Pure by Architecture."*
> **[EliteAgent v8.1 — Titan Optimized — UNO Pure]**
