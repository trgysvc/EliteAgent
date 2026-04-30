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

## Verification Plan
- **Parity Tests:** `XCTAssertEqual(hfTokens, bpeTokens)`.
- **Pressure Simulation:** Use `memory_pressure` CLI to trigger kernel signals and verify session freezing.
- **UNO Latency:** Measure time-to-first-token with large vision/file payloads before and after Pointer Migration.
