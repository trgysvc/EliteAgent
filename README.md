# 🛸 EliteAgent

<p align="center">
  <b>A fully autonomous and hardware-aware Hybrid Intelligence Agent running on your desktop.</b><br>
  <i>Powered by the <b>UNO (Unified Native Orchestration)</b> architecture, featuring distributed actors and Apple Silicon optimization.</i>
</p>

---

## 🚀 Project Status: v7.0 Stability Sprint [ACTIVE]

EliteAgent is currently in **Phase 7 (Stability & Validation)** of the v7.0 roadmap. This sprint successfully transitioned the core from a text-heavy bridge to a high-performance, binary-native orchestration system.

### Recent Achievements:
- **UMA Watchdog & Proactive Monitor**: Real-time M-series memory pressure handling with zero-copy buffer recycling.
- **Zero-Copy UNO Architecture**: Complete elimination of JSON for internal actor communication, using `SharedMemoryPool` for lightning-fast state transfers.
- **MCP Native Integration**: Session-scoped Model Context Protocol support via `stdio` transport, enabling external tool expansion.
- **Native BrowserAgent**: Retired `chrome-mcp` dependency in favor of a native `AXUIElement` + `SafariJSBridge` engine for high-fidelity web automation.

### Feature Comparison: EliteAgent vs. OpenClaw
| Feature | OpenClaw | **EliteAgent (v7.0)** |
| :--- | :---: | :---: |
| **Transport** | JSON-RPC (String) | **UNO Binary (Zero-Copy)** |
| **Inference** | Python/PyTorch | **Native MLX (Apple Silicon)** |
| **UI Automation** | Selenium/Playwright | **Native AX + Safari Bridge** |
| **Memory** | Vector DB only | **Proactive UMA Monitoring** |
| **Extensibility** | Manual Scripts | **Native MCP + PluginCraft** |

---

## 🛠 Tool Inventory (Master Registry)

EliteAgent v7.0 features a hardened suite of tools, each identified by a **Unique Binary ID (UBID)** for high-precision model triggering.

### 🌐 Browser & Research
- **`browser_native` (UBID 47)**: Interactive Safari controller (Navigate, Read, Fill, Tab Mgmt, AX Inspection).
- **`web_search` (UBID 45)**: Real-time search via Google/Brave API.
- **`web_fetch` (UBID 46)**: Clean markdown extraction from any URL.
- **`safari_automation` (UBID 40)**: Legacy AppleScript-based Safari control.

### 💻 System & Automation
- **`shell_exec` (UBID 32)**: Secure zsh/terminal execution.
- **`apple_accessibility` (UBID 24)**: Direct `AXUIElement` interaction for native Mac apps.
- **`run_shortcut` (UBID 49)**: Native macOS Shortcuts integration.
- **`app_launcher` (UBID 88)**: Secure application lifecycle management.
- **`system_telemetry` (UBID 36)**: M-series thermal and RAM pressure monitoring.

### 📂 File & Code
- **`read_file` (UBID 33)** / **`write_file` (UBID 34)**: High-speed IO with PDF/Docx support.
- **`patch_file` (UBID 41)**: Atomic diff-based code modification.
- **`git_action` (UBID 42)**: Native Git workflow management.
- **`xcode_engine` (UBID 47*)**: Deep integration for building and debugging Swift projects.

### 🧠 Memory & Logic
- **`memory` (UBID 44)**: L2 vector storage for long-term cognitive data.
- **`subagent_spawn` (UBID 19)**: Recursive sub-task orchestration.
- **`calculator_op` (UBID 58)**: High-precision mathematical engine.

### 🔌 MCP (Model Context Protocol)
- **`serverName__toolName`**: Automated routing to local MCP servers (configured in `vault.plist`).

---

## 🏗 Architecture: UNO (Unified Native Orchestration)

EliteAgent v7.0 enforces a **JSON-Free** internal highway.

### Core Components:
- **`SharedMemoryPool`**: Manages zero-copy transfer of large context blocks between `InferenceActor` and `Orchestrator` using memory mapping.
- **`ProactiveMemoryPressureMonitor`**: A real-time watchdog that triggers `KV-Cache` shrinking or tool suspension when M-series UMA pressure exceeds 85%.
- **`SignalBus`**: A biometrically secured binary signal highway for inter-agent communication.

> **Rule of UNO**: JSON is strictly prohibited for internal state. JSON is only permitted at the **MCP boundary** (external protocol requirement) and is immediately converted to binary PropertyLists upon ingestion.

---

## ⚙️ Installation & Setup

### Requirements
- **Operating System:** macOS 15.0 or later.
- **Processor:** Apple Silicon (M1/M2/M3/M4, etc.).
- **Memory:** 16GB RAM minimum recommended.
- **Development Environment:** Xcode 16.0 or later.

### Dependencies
- **`mlx-swift`**: Primary local inference engine.
- **`modelcontextprotocol/swift-sdk`**: Native MCP client support.
- *REMOVED: `swift-transformers` (Replaced by native MLX implementations for zero-copy compatibility).*

### MCP Configuration (`vault.plist`)
To enable external MCP tools, add your servers to `~/Library/Application Support/EliteAgent/vault.plist`:
```xml
<key>mcpServers</key>
<array>
    <dict>
        <key>name</key>
        <string>google-maps</string>
        <key>command</key>
        <string>npx</string>
        <key>args</key>
        <array><string>-y</string><string>@modelcontextprotocol/server-google-maps</string></array>
    </dict>
</array>
```

---

> *"Privacy by Design. Autonomy by Nature. Forensic by Intent. Native by Choice. Evolution by Recursive Logic. Hardware by Mastery. Pure by Architecture."*  
> **[EliteAgent Core - v20.0.0 UNO Pure - OFFICIAL IRON SEALED - v7.0 STABILITY SPRINT]**
