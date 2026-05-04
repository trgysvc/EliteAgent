# GEMINI.md — EliteAgent Project Rules for Antigravity

This file is read by Gemini CLI (Antigravity) at session start.
**These rules are absolute. Violations break the architecture and have caused production bugs.**

---

## ⛔ CRITICAL: ZERO JSON IN PRODUCTION CODE

**THIS RULE WAS VIOLATED ON 2026-05-03. IT MUST NEVER HAPPEN AGAIN.**

The following are **COMPLETELY FORBIDDEN** in any source file except `UNOExternalBridge.swift`:

```swift
JSONEncoder()           // FORBIDDEN
JSONDecoder()           // FORBIDDEN
JSONSerialization       // FORBIDDEN
.jsonObject(            // FORBIDDEN
try? JSONEncoder()      // FORBIDDEN
try! JSONDecoder()      // FORBIDDEN
```

**No exceptions. No "just this once". No "it's only for config".**

### Why?

EliteAgent is built on the UNO (Unified Native Orchestration) architecture. All internal communication uses **binary PropertyList**. JSON is a transport-level protocol for external systems only. When JSON is used internally:
- It breaks the actor isolation model (untyped Any values cross Sendable boundaries)
- It creates silent data corruption risks (JSON rounding of numbers, etc.)
- It violates the explicit architectural contract the owner has defined

### What to use instead:

| Instead of | Use |
|---|---|
| `JSONEncoder().encode(x)` | `PropertyListEncoder(outputFormat: .binary).encode(x)` |
| `JSONDecoder().decode(T, from: data)` | `PropertyListDecoder().decode(T, from: data)` |
| `JSONSerialization.jsonObject(...)` | `PropertyListSerialization.propertyList(...)` |
| `[String: Any]` across boundaries | `AnyCodable` or typed struct |

### The ONE legal exception:

```swift
// UNOExternalBridge.swift — the only file allowed to touch JSON
UNOExternalBridge.shared.encode(myValue)
UNOExternalBridge.shared.decode(MyType.self, from: data)

// HTTP response bodies in LocalInferenceServer (Ollama-compat)
// are OK because they ARE the external protocol being served.
```

---

## ⛔ ZERO DispatchQueue

**FORBIDDEN in all application code:**
```swift
DispatchQueue.global()
DispatchQueue(label: ...)
DispatchSemaphore
DispatchGroup
```

**Use instead:** `async/await`, `Task`, `TaskGroup`, `actor`, `AsyncStream`

**Known exception (Apple API constraint):** `FSEventStreamSetDispatchQueue` in `ProjectObserver.swift` — Apple's FSEvents API requires a DispatchQueue. This is the only acceptable exception and is documented in DEVLOG.

---

## ⛔ ZERO FORCE UNWRAP

```swift
let x = foo!      // FORBIDDEN
foo as! Bar       // FORBIDDEN
```

Use `guard let`, `if let`, `try?`, `as?`.

---

## Architecture Snapshot (as of 2026-05-04)

### Source Targets
- `Sources/EliteAgent/` — SwiftUI app entry point
- `Sources/EliteAgentCore/` — All business logic
  - `AgentEngine/` — Orchestrator, OrchestratorRuntime, PlannerTemplate, sub-agents
  - `LLM/` — InferenceActor (Titan Engine), MLXProvider, CloudProvider, ModelCatalog
  - `ToolEngine/` — AgentTool protocol, ToolRegistry, ToolIDs, tool implementations
  - `UNO/` — UNODistributedActorSystem, UNOTransport, UNOExternalBridge
  - `Config/` — PathConfiguration (single source of truth for all paths)
- `Sources/EliteAgentUI/` — Reusable UI components
- `Sources/EliteAgentXPC/` — XPC helper process
- `Sources/elite/` — CLI PVP tool
- `Sources/uma-bench/` — UMA benchmark

### Key Files
| File | Role |
|---|---|
| `InferenceActor.swift` | Titan Engine — MLX model load, generate, speculative decoding, wired memory |
| `MLXProvider.swift` | Bridges CompletionRequest → InferenceActor, extracts think blocks |
| `OrchestratorRuntime.swift` | Plan→Execute→Reflect loop, tool dispatch, intent classification |
| `PlannerTemplate.swift` | System prompt builder for agentic and native tool calling paths |
| `ToolRegistry.swift` | Dual-indexed (name + UBID) tool registry actor |
| `UNOExternalBridge.swift` | ONLY legal JSON surface — encode/decode for external protocols |
| `PathConfiguration.swift` | All file paths — never hardcode paths |
| `ModelCatalog.swift` | Model registry — add new models here |

### Data Flow (Local Inference)
```
User Input
  → Orchestrator (MainActor)
  → OrchestratorRuntime.actor
    → intent classification (MLXProvider, complexity=1, enableThinking=false)
    → if chat: handleChatting() → MLXProvider.complete()
    → if task: handlePlanning() → MLXProvider.complete() (enableThinking=true)
      → handleExecution() → ToolRegistry dispatch
  → InferenceActor (actor)
    → ModelContainer.prepare(UserInput) → LMInput
    → ModelContainer.generate(LMInput, GenerateParameters, wiredMemoryTicket?)
    → AsyncStream<Generation> → InferenceChunk stream
  → MLXProvider extracts think blocks, collects tool calls
  → CompletionResponse → OrchestratorRuntime
```

### GenerateParameters (current config)
```swift
temperature = 0.6, topP = 0.9, minP = 0.05
repetitionPenalty = 1.15, repetitionContextSize = 64
kvBits = 4, kvGroupSize = 64, quantizedKVStart = 256
maxKVSize = 8192   // Rotating KV Cache (Item 5)
```

### Wired Memory (Item 4)
After `loadModel()`, `WiredMemoryUtils.tune()` runs in background, stores `wiredMeasurement`. Each `generate()` creates a `WiredBudgetPolicy` ticket and passes it to `container.generate(wiredMemoryTicket:)`.

### Speculative Decoding (Item 6)
If a draft model exists at `{mainModelURL}-draft` or is loaded via `loadDraftModel(at:)`, generation uses `MLXLMCommon.generate(input:parameters:context:draftModel:numDraftTokens:4:)`.

---

## Tool System Rules

- Every tool has a `ubid: Int128` (Unique Binary ID) from `ToolUBID` enum in `ToolIDs.swift`
- Tools are registered via `ToolRegistry.shared.register(MyTool())`
- Tool execution is dispatched via UBID, never by string name matching internally
- New tools MUST get a `ToolUBID` case BEFORE being registered

## Adding a New Tool

1. Add `case myTool = <unique_int128>` in `ToolIDs.swift`
2. Create `struct MyTool: AgentTool, Sendable` in `Sources/EliteAgentCore/ToolEngine/Tools/`
3. Set `ubid = ToolUBID.myTool.rawValue`
4. Register: `ToolRegistry.shared.register(MyTool())`

---

## DEVLOG Requirement

After every completed task, **append** (never overwrite) an entry to `Resources/Config/DEVLOG.md`:

```
### [YYYY-MM-DD] — {Task Summary}
**What changed:** ...
**Files modified:** ...
**Decision made:** ...
**Next:** ...
```

---

## Paths (never hardcode)

```swift
PathConfiguration.shared.modelsURL        // ~/Library/Application Support/EliteAgent/Models/
PathConfiguration.shared.vaultURL         // ~/Library/Application Support/EliteAgent/vault.plist
PathConfiguration.shared.logsURL          // ~/Library/Logs/EliteAgent/
// Workspace (excluded from factory resets):
// ~/Workspaces/EliteAgent/
```

---

## Build Commands

```bash
swift build          # Debug
swift build -c release  # Release
swift test           # All tests
```

Swift 6.3.0, macOS 15+, Xcode 16+, Apple Silicon only.
