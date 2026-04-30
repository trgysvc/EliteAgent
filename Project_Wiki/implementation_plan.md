# Implementation Plan: EliteAgent v7.0 Stability Sprint (Refined)

## Mission: Native Sovereign Stability
Formalize EliteAgent v7.0 Stability by implementing proactive hardware-level memory management, zero-copy pointer-native orchestration, and native MLX optimization.

## Proposed Changes

### Phase 1: Proactive UMA Watchdog & Stability
- **Implementation:** Integrate `ProactiveMemoryPressureMonitor` with `OrchestratorRuntime`.
- **Session Freeze Logic:** 
    - `.warning`: Trigger context compaction (compaction).
    - `.critical`: `pauseAllSessions()`, `forceConsolidate()` (blocking), and freeze all inference until pressure drops.
- **HardwareMonitor:** Update to report real-time kernel pressure levels.

### Phase 2: UNO Pointer Migration & Tool Result Lifecycle
- **SharedMemoryPool (Actor):** Manage `xpc_shmem_t` lifecycles centrally.
- **Dual-Path Transport:**
    - `<64KB`: Inline binary PropertyList.
    - `>64KB`: `SharedMemoryBuffer` + UUID reference (zero-copy).
- **Tool Result Cap:** Implement a hard cap for LLM input (truncated view) while preserving full data in the SharedMemoryPool/Session.

### Phase 3: Context & Failure Management (openclaw Integration)
- **Preemptive Overflow Check:** Use actual MLX tokenizer counts in `ContextWindowGuard` instead of estimates.
- **Typed Failover Policy:** Centralize recovery logic into a pure decision function with `PrivacyGuard` awareness.
- **DreamActor Refinement:** Implement `summarizeToolResults` to preserve the causality chain while shrinking context. Preserve UUIDs, file paths, and progress markers.

### Phase 4: MLX-Native Cleanup
- **Parity Validation:** Rigorous testing of `BPETokenizer` vs `HFTokenizer` to ensure zero vocab mismatch.
- **Dependency Removal:** Strip `swift-transformers` and `Tokenizers` library from the codebase.

### Phase 5: MCP Integration (Model Context Protocol)
- **Goal:** Add session-scoped MCP client to enable external tool integrations (web search, calendar, email, etc.) via the standardized Model Context Protocol.
- **Key Actions:**
    - Implement `MCPClientActor` using the `modelcontextprotocol/swift-sdk`.
    - Support `stdio` transport for local MCP servers with session-scoped lifecycle management.
    - Implement automatic tool registration using the `serverName__toolName` mapping pattern.
    - Integrate with `VaultManager` for secure MCP server configuration storage.
    
### Phase 6: BrowserAgent Polish
- **Goal:** Replace legacy `WKWebView` automation with a high-fidelity native Safari engine.
- **Key Actions:**
    - Enhance `SafariJSBridge` with window/tab management and robust error reporting.
    - Implement `BrowserAXInspector` to provide the LLM with a navigable AX-tree of the active page.
    - Transition `NativeBrowserTool` from internal web views to direct Safari control via AX + AppleScript.

## Execution History & Status

### 🟢 Phase 1: Proactive UMA Watchdog (Completed)
- **Status:** ✅ 100% Native Implementation.
- **Key Files:** `OrchestratorRuntime.swift`, `HardwareMonitor.swift`, `ProactiveMemoryPressureMonitor.swift`.
- **Architecture Decisions:** 
    - Implemented a global session freeze mechanism via `@MainActor` state in `OrchestratorRuntime`.
    - Integrated kernel memory pressure signals (`.warning`, `.critical`) to trigger proactive compaction.
- **Test Coverage:** Verified via manual memory pressure simulation and telemetry logging.

### 🟢 Phase 2: UNO Pointer Migration (Completed)
- **Status:** ✅ Zero-Copy Optimized.
- **Key Files:** `SharedMemoryPool.swift`, `UNOTransport.swift`, `ToolRegistry.swift`, `Session.swift`.
- **Architecture Decisions:** 
    - Established a 64KB threshold for dual-path transport (Inline vs. Shared Memory).
    - Implemented "Smart Truncation" (32K char cap) for LLM context, while preserving 100% of data in the `Session` actor for causality integrity.
- **Test Coverage:** Logged output size transitions and verified pointer retrieval in `UNOTransport`.

### 🟢 Phase 3: Context & Failure Management (Completed)
- **Status:** ✅ Preemptive Protection Active.
- **Key Files:** `ContextWindowGuard.swift`, `FailoverPolicy.swift`, `DreamActor.swift`.
- **Architecture Decisions:** 
    - Adopted a 1.2x margin for preemptive context overflow checks (OpenClaw approach).
    - Consolidated recovery logic into `FailoverPolicy` to eliminate fragmented "Self-Healing" engines.
    - Updated `DreamActor` prompt to preserve structural identifiers (UUIDs/Paths) while stripping noisy tool data.
- **Test Coverage:** Verified projected usage logic against 8K context limits.

### 🟢 Phase 4: MLX-Native Cleanup (Completed)
- **Status:** ✅ Native Sovereign Achieved.
- **Key Files:** `Tokenizer.swift`, `InferenceActor.swift`, `UNOGrammarLogitProcessor.swift`.
- **Architecture Decisions:** 
    - Replaced `swift-transformers` with a localized `BPETokenizer` implementation.
    - Decoupled `UNOGrammarLogitProcessor` from external tokenizer types using a native `UNOTokenizer` protocol.
- **Test Coverage:** Standalone parity script verified 1:1 token matching with Qwen 2.5 vocabulary.

### 🟢 Phase 5: MCP Integration (Completed)
- **Status:** ✅ Protocol-Neutral Extension Active.
- **Key Files:** `MCPClientActor.swift`, `VaultManager.swift`, `ToolRegistry.swift`.
- **Architecture Decisions:** 
    - Adopted a "JSON-at-boundary" strategy: JSON is used for external MCP communication but immediately converted to UNO Binary (PropertyList) for internal processing.
    - Implemented tool auto-registration using `serverName__toolName` to prevent namespace collisions.
- **Test Coverage:** Verified tool listing and execution using local MCP servers (stdio).

### 🟢 Phase 6: BrowserAgent Polish (Completed)
- **Status:** ✅ Native Safari Mastery.
- **Key Files:** `SafariJSBridge.swift`, `BrowserAgent.swift`, `BrowserAXInspector.swift`, `NativeBrowserTool.swift`.
- **Architecture Decisions:** 
    - Prioritized `AXUIElement` for direct OS-level interaction (form filling, clicking) with AppleScript as a fallback.
    - Implemented a 10-level depth limit for AX tree dumps to maintain high performance during inspection.
- **Test Coverage:** Verified tab switching and AX tree dumping in Safari.

## Verification Plan (Phase 7 Next)
- **Parity Tests:** `XCTAssertEqual(hfTokens, bpeTokens)`. (Completed)
- **Pressure Simulation:** Use `memory_pressure` CLI to trigger kernel signals and verify session freezing. (Completed)
- **Browser Validation:** Execute high-fidelity automation scripts against Gmail and GitHub to verify AX discovery. (Pending)
