# Task List: EliteAgent v7.0 Stability Sprint

- [x] **Phase 1: Proactive UMA Watchdog & Stability**
    - [x] Implement `OrchestratorRuntime.pauseAllSessions()` and `resumeAllSessions()`.
    - [x] Integrate `.critical` pressure signal to trigger emergency session freeze and `forceConsolidate`.
    - [x] Update `HardwareMonitor` to report real-time `memoryPressureLevel`.
    - [x] Verify session pause/resume flow during simulated memory pressure.

- [x] **Phase 2: UNO Pointer Migration & Tool Result Lifecycle**
    - [x] Create `SharedMemoryPool` actor for `xpc_shmem_t` lifecycle management.
    - [x] Refactor `UNOTransport` to handle dual-path (inline vs shmem) data transfer (64KB threshold).
    - [x] Implement `ToolResult` truncation logic for LLM input while preserving original data in session (32K char cap).

- [x] **Phase 3: Context & Failure Management**
    - [x] Implement preemptive overflow check in `ContextWindowGuard.swift` (1.2x Margin).
    - [x] Create `FailoverPolicy.swift` with typed `FailoverReason` and `resolveFailoverAction()`.
    - [x] Refine `DreamActor` compaction instructions (Preserve IDs/Progress, Strip tool details).

- [x] **Phase 4: MLX-Native Cleanup**
    - [x] Implement Tokenizer Parity Test Suite (Standalone Script).
    - [x] Integrate `BPETokenizer` into `InferenceActor` and `UNOGrammarLogitProcessor`.
    - [x] Remove direct `Tokenizers` and `Transformers` imports.
    - [x] Final architecture audit.

- [x] **Phase 5: MCP Integration (Model Context Protocol)**
    - [x] Add `MCPClientActor` using MCP Swift SDK.
    - [x] Implement `stdio` transport for local MCP servers.
    - [x] Design session-scoped runtime (sessionId + serverName).
    - [x] Implement tool auto-registration (`serverName__toolName`).
    - [x] Add 10-min idle TTL and 60s sweep timer.
    - [x] Update `VaultManager` with `mcpServers` support in `vault.plist`.

- [x] **Phase 6: BrowserAgent Polish**
    - [x] Enhance `SafariJSBridge` with tab management (`listTabs`, `switchToTab`).
    - [x] Implement native AX-based element discovery and form filling.
    - [x] Create `BrowserAXInspector` for UI tree analysis.
    - [x] Wire `NativeBrowserTool` to Safari backend (removing `WKWebView` reliance).

- [/] **Phase 7: Validation & Test Suite (Next)**
    - [ ] Run automated parity tests for all tools.
    - [ ] Perform real-world browser automation tests (Gmail/Drive/GitHub).
    - [ ] Verify UMA pressure handling under heavy load.
    - [ ] Final security audit of `vault.plist` domain restrictions.
