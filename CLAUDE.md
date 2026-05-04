# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

---

## ⛔ ABSOLUTE RULES — READ BEFORE TOUCHING ANY FILE

These rules are non-negotiable. Violating them breaks the architecture and has caused production bugs.

### 1. ZERO JSON IN PRODUCTION CODE

**FORBIDDEN — never write these anywhere except inside `UNOExternalBridge.swift`:**
```swift
JSONEncoder()          // FORBIDDEN
JSONDecoder()          // FORBIDDEN
JSONSerialization      // FORBIDDEN
.jsonObject(           // FORBIDDEN
try? JSONEncoder()     // FORBIDDEN
```

**WHY:** EliteAgent uses binary PropertyList (UNO protocol) for all internal actor communication. JSON was explicitly chosen as a transport-level concern only, not a data format. Every time JSON leaks into non-bridge code, it creates a type-safety hole and a Sendable violation.

**ALLOWED — the only legal JSON surface:**
```swift
// UNOExternalBridge.swift is the ONLY file allowed to touch JSON
UNOExternalBridge.shared.encode(...)      // OK
UNOExternalBridge.shared.decode(...)      // OK
// HTTP server responses (LocalInferenceServer, Ollama-compat layer) — OK because it IS the external protocol
```

**What to use instead:**
```swift
PropertyListEncoder(outputFormat: .binary)  // for Data serialization
PropertyListDecoder()                        // for Data deserialization
AnyCodable(value)                           // for heterogeneous values across actors
```

### 2. ZERO DispatchQueue

**FORBIDDEN:**
```swift
DispatchQueue.global()     // FORBIDDEN
DispatchQueue.main         // FORBIDDEN (except FSEventStreamSetDispatchQueue — Apple API limit, documented in DEVLOG)
DispatchSemaphore          // FORBIDDEN
```

**Use instead:** `async/await`, `Task`, `TaskGroup`, `actor`, `AsyncStream`

### 3. ZERO FORCE UNWRAP in production code

```swift
let x = foo!         // FORBIDDEN
foo as! Bar          // FORBIDDEN — use guard let with as?
```

**Use instead:** `guard let`, `if let`, `try?`, `as?`

### 4. NO UNTYPED DICTIONARIES ACROSS ACTOR/XPC BOUNDARIES

`[String: Any]` and `[String: AnyObject]` cannot cross actor or XPC isolation safely. Use typed structs, `AnyCodable`, or binary plist.

---

## Build & Run

```bash
# Debug build (SPM)
swift build

# Release build
swift build -c release

# Run tests
swift test

# Run a single test
swift test --filter EliteAgentTests/testFactoryReset_DeletesGGUFFiles

# CLI tool (runs the agent from terminal)
swift run elite "<task description>"
swift run elite "<task>" --cloud-only
swift run elite "<task>" --local-only
swift run elite --benchmark
swift run elite --verify-pvp   # PVP hardware/health verification

# Build via Xcode (required for signing/entitlements)
xcodebuild -project EliteAgent.xcodeproj -scheme EliteAgent -configuration Debug build
```

**Swift version:** 6.3.0 (see `.swift-version`). Requires macOS 15+ and Xcode 16+. Apple Silicon only.

---

## Architecture

EliteAgent is a native macOS autonomous agent built on the **UNO (Unified Native Orchestration)** architecture — distributed actors with binary-native IPC, no JSON anywhere.

### Targets (Package.swift)

| Target | Type | Role |
|---|---|---|
| `EliteAgent` | Executable | SwiftUI macOS app — entry point, wires up UI and core |
| `EliteAgentCore` | Dynamic Library | All business logic: inference, tools, memory, orchestration |
| `EliteAgentUI` | Library | Reusable UI components (NeuralSightCards, TulparView) |
| `EliteAgentXPC` | Executable | XPC helper process for sandboxed operations |
| `elite` | Executable | CLI PVP verification and direct task runner |
| `uma-bench` | Executable | Unified Memory Architecture benchmark harness |

### Core Subsystems

**Orchestration Layer** (`Sources/EliteAgentCore/AgentEngine/`)
- `Orchestrator.swift` — `@MainActor ObservableObject`. UI-facing coordinator that owns the task queue, session history, and published state. Delegates actual inference to `OrchestratorRuntime`.
- `OrchestratorRuntime.swift` — `actor`. The stateless inference driver. Runs the plan→execute→reflect loop, calls LLM providers, dispatches tool calls. Stateless by design to prevent memory leaks.
- `EliteCoordinator.swift` — `actor`. Parallel task decomposition with dependency graph and resource locking.
- `PlannerAgent`, `CriticAgent`, `MemoryAgent`, `GuardAgent` — specialized sub-agents with distinct roles in the reasoning pipeline.

**LLM Provider Layer** (`Sources/EliteAgentCore/LLM/`)
- `LLMProvider.swift` — Protocol: `Actor` with `complete(_:useSafeMode:)`.
- `MLXProvider.swift` — Local inference; bridges to `InferenceActor.shared` (Titan Engine running MLX).
- `InferenceActor.swift` — `actor`. Owns the loaded MLX model, GPU/ANE state, wired memory measurement, and optional draft model for speculative decoding.
- `CloudProvider.swift` — Cloud inference via OpenRouter (or any OpenAI-compatible endpoint). Config driven by `VaultManager`.
- Provider config lives in `vault.plist` (`~/Library/Application Support/EliteAgent/vault.plist`), API keys in Keychain via `VaultManager`.

**Tool System** (`Sources/EliteAgentCore/ToolEngine/`)
- `AgentTool.swift` — Protocol with `ubid: Int128` (Unique Binary ID), `execute(params:session:)`.
- `ToolRegistry.swift` — `actor`. Dual-indexed map: by name and by UBID. Use `ToolRegistry.shared`.
- `ToolIDs.swift` — `ToolUBID` enum: the sealed UBID census. Every tool must have an entry here.
- `ToolEngine.swift` — `actor`. Loads `ToolDefinition` descriptors from `.plist` files (binary plist, not JSON).
- Concrete tools live in `Sources/EliteAgentCore/ToolEngine/Tools/`.

**UNO Transport** (`Sources/EliteAgentCore/UNO/`)
- `UNODistributedActorSystem.swift` — custom `DistributedActorSystem` over XPC. All cross-process calls go through here, not strings.

**Configuration & Storage** (`Sources/EliteAgentCore/Config/`)
- `PathConfiguration.swift` — All standard macOS paths. Always use `PathConfiguration.shared.*URL` instead of hardcoding paths.
  - Models: `~/Library/Application Support/EliteAgent/Models/`
  - Workspace: `~/Workspaces/EliteAgent/` (excluded from factory resets)
  - Logs: `~/Library/Logs/EliteAgent/`

### UNO Rules (Non-Negotiable)

- **No JSON.** Zero `JSONEncoder`/`JSONDecoder`/`JSONSerialization` in production code. Route through `UNOExternalBridge` if external JSON parsing is unavoidable.
- **No `DispatchQueue`.** All concurrency via `async/await`, `TaskGroup`, and `actor`. Exception: `FSEventStreamSetDispatchQueue` is an Apple API constraint, documented in DEVLOG.
- **No force unwrap (`!`)** in production code. Use `guard let` / `if let`.
- **No `Any` or untyped dictionaries** across actor/XPC boundaries.
- Tool invocations must use the UBID lookup path, not string matching.
- New tools require a `ToolUBID` case in `ToolIDs.swift` before they can be registered.

### Adding a New Tool

1. Add a `case myTool = <unique_int128>` to `ToolUBID` in `ToolIDs.swift`.
2. Create a `struct MyTool: AgentTool, Sendable` in `Sources/EliteAgentCore/ToolEngine/Tools/`.
3. Set `ubid` to `ToolUBID.myTool.rawValue`.
4. Register in `Orchestrator`'s tool setup block via `ToolRegistry.shared.register(MyTool())`.

### Key LLM Architecture (v3 Native)

- `InferenceActor.generate()` uses `container.generate(input:parameters:wiredMemoryTicket:)` for regular inference.
- Speculative decoding activates automatically when `draftModelContainer` is loaded (draft model at `{mainModelURL}-draft` or via `loadDraftModel(at:)`).
- `enableThinking: false` → `additionalContext["enable_thinking": false]` suppresses Qwen 3.5 `<think>` blocks for chat (complexity == 1).
- `enableThinking: true` is default for planning/tool-use (complexity > 1).
- GenerateParameters configured in `InferenceActor.generate()`: kvBits=4, kvGroupSize=64, maxKVSize=8192, repetitionPenalty=1.15, topP=0.9, minP=0.05.

---

## DEVLOG Requirement

After every completed task, **append** an entry to `Resources/Config/DEVLOG.md`:

```
### [YYYY-MM-DD] — {Task Summary}
**What changed:** {Brief description}
**Files modified:** {List of affected files}
**Decision made:** {Any architectural or technical decision, if applicable}
**Next:** {Follow-up task or open question, if any}
```

DEVLOG entries are **append-only**. Never edit or delete previous entries.

---

## Key Dependencies

- `mlx-swift` / `mlx-swift-lm` — Apple Silicon GPU/ANE inference. Use unified memory; never copy CPU↔GPU explicitly.
- `Sparkle` — Auto-update framework.
- `audiointelligence` (private, `trgysvc/audiointelligence`) — DSP/audio analysis library.

`Package.resolved` is tracked in git. All contributors use identical library versions.
