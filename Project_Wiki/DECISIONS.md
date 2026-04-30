# Architectural Decisions: EliteAgent v7.0 Stability Sprint

## [2026-04-30] ADR-001: Global Session Control for UMA Watchdog
- **Decision:** Implement `pauseAllSessions()` and `resumeAllSessions()` as `@MainActor` static methods in `OrchestratorRuntime`.
- **Rationale:** Ensures thread-safe, instantaneous freezing of all inference sessions when kernel memory pressure reaches `.critical`.
- **Impact:** Prevents OOM crashes by halting new token generation until pressure subsides.

## [2026-04-30] ADR-002: Dual-Path UNO Transport (Zero-Copy)
- **Decision:** Establish a 64KB threshold for dual-path IPC. 
    - `< 64KB`: Inline binary PropertyList (low overhead).
    - `> 64KB`: `SharedMemoryPool` (Actor) + `xpc_shmem_t` (Zero-copy).
- **Rationale:** Avoids the performance penalty of copying large data blocks (vision payloads, logs) across XPC boundaries.
- **Impact:** Significant reduction in IPC latency for data-heavy tool executions.

## [2026-04-30] ADR-003: Smart Tool Result Truncation
- **Decision:** Implement a 32,000 character (~8k token) "Hard Cap" for tool results passed to the LLM context.
- **Rationale:** Protects the KV Cache from being overwhelmed by massive tool outputs (e.g., 50k line file reads).
- **Impact:** Preserves context space for reasoning while storing full results in the `Session` actor for causality integrity.

## [2026-04-30] ADR-004: Preemptive Context Overflow Protection
- **Decision:** Adopt the formula `(Current + System + Predicted Response) * 1.2 > Budget` in `ContextWindowGuard`.
- **Rationale:** 20% safety margin accounts for tokenization variance and multi-turn expansion, triggering compaction before reaching hard limits.
- **Impact:** Eliminates "400 Context Overflow" errors during complex autonomous workflows.

## [2026-04-30] ADR-005: Native Sovereign Tokenization
- **Decision:** Replace `swift-transformers` with a native `BPETokenizer` and `UNOTokenizer` protocol.
- **Rationale:** Removes massive external dependency chain and ensures the core inference loop is isolated from library updates.
- **Impact:** Faster startup times and simplified binary distribution.

## [2026-04-30] ADR-006: Session-Scoped MCP Client Architecture
- **Decision:** Implement MCP clients as session-scoped entities managed by `MCPClientActor`.
- **Rationale:** Standardizes external tool integration (search, calendar) without polluting the core toolset. Session-scoping ensures resource isolation and security.
- **Impact:** Enables highly extensible tool discovery while maintaining 10-minute idle TTL for memory safety.

## [2026-05-01] ADR-007: JSON-to-Binary Boundary Strategy for MCP
- **Decision:** Use JSON only at the MCP protocol boundary; convert all incoming payloads to UNO Binary (PropertyList) for internal routing.
- **Rationale:** Maintains the project's "No JSON" rule for internal orchestration while complying with the external MCP standard.
- **Impact:** Ensures internal type safety and performance while allowing external extensibility.

## [2026-05-01] ADR-008: Native AX-First Browser Automation
- **Decision:** Prioritize `AXUIElement` (Accessibility API) for browser interaction, using `SafariJSBridge` (JavaScript) only as a fallback.
- **Rationale:** Native AX interaction is more robust against complex DOM structures (like SPAs) and bypasses many anti-automation detections.
- **Impact:** Higher fidelity automation for sites like Gmail, GitHub, and Google Drive.
