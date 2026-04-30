# Task List: EliteAgent v7.0 Stability Sprint

- [x] **Phase 1: Proactive UMA Watchdog & Stability**
    - [x] Implement `OrchestratorRuntime.pauseAllSessions()` and `resumeAllSessions()`.
    - [x] Integrate `.critical` pressure signal to trigger emergency session freeze and `forceConsolidate`.
    - [x] Update `HardwareMonitor` to report real-time `memoryPressureLevel`.
    - [x] Verify session pause/resume flow during simulated memory pressure.

- [ ] **Phase 2: UNO Pointer Migration & Tool Result Lifecycle**
    - [ ] Create `SharedMemoryPool` actor for `xpc_shmem_t` lifecycle management.
    - [ ] Refactor `UNOTransport` to handle dual-path (inline vs shmem) data transfer.
    - [ ] Implement `ToolResult` truncation logic for LLM input while preserving original data in session.

- [ ] **Phase 3: Context & Failure Management**
    - [ ] Refactor `ContextWindowGuard` to use actual MLX token counts.
    - [ ] Implement `FailoverPolicy.swift` with pure decision logic and Privacy Guard checks.
    - [ ] Update `DreamActor` with `summarizeToolResults` logic and identifier preservation.

- [ ] **Phase 4: MLX-Native Cleanup**
    - [ ] Implement Tokenizer Parity Test Suite.
    - [ ] Remove `Tokenizers` and `Transformers` dependencies from `Package.swift` and source files.
    - [ ] Final architecture audit.
