# v3-Native Migration Guide (EliteAgent v7.1)

## Overview
EliteAgent v7.1 "Native Sovereign" completes the transition from the legacy `mlx-swift-lm` v2 architecture to the official **v3.31.3 Stable** ecosystem. This migration decouples the core inference engine from specific tokenizer and downloader implementations, achieving higher modularity and Swift 6 concurrency safety.

## Key Architectural Changes

### 1. Modular Dependency Stack
In v3, dependencies are no longer bundled into a single package. EliteAgent now explicitly integrates:
- **MLXLMTokenizers**: Handles tokenizer orchestration via `AutoTokenizer`.
- **MLXLMHFAPI**: Provides Hugging Face Hub client integration.
- **MLXHuggingFace**: Enables official macros like `#huggingFaceTokenizerLoader()`.

### 2. Model Loading (v3 Standards)
The legacy `LLMModelFactory.loadContainer` pattern has been replaced with the official global **`loadModelContainer`** function.
- **Local Loading**: Uses `loadModelContainer(from: URL)` for automated directory scanning.
- **Tokenizer Injection**: Uses `#huggingFaceTokenizerLoader()` for official Hugging Face compatibility.

### 3. Swift 6.1 & SPM Traits
v3.31.3 requires **Swift 6.1+** to support the new SPM **Traits** feature utilized by `swift-tokenizers-mlx`.
- **Package.swift**: `swift-tools-version` must be set to `6.1`.
- **Toolchain**: macOS 15.0+ with Xcode 16.1+ is mandatory for Titan Engine optimization.

### 4. Model Context Protocol (MCP) Integration
EliteAgent now officially supports the **Model Context Protocol (MCP)** via the `swift-sdk`.
- **EliteAgentCore**: Integrates `MCP` products for standardized tool-calling and resource sharing.
- **Architectural Shift**: Moving towards a protocol-first tool orchestration model, decoupling AI logic from local tool implementations.

### 5. yyjson Module Stabilization
Legacy `unsafeFlags` hacks for `yyjson` have been removed in favor of official SPM linking.
- **Module Mapping**: Using standard `.product(name: "yyjson", package: "yyjson")` to ensure Xcode indexing compatibility.
- **Binary Safety**: Adhering to the UNO (Unified Native Orchestration) policy of binary-only data transfer.

### 6. Swift 6 Concurrency & XPC
To support the strict concurrency requirements of Swift 6:
- **@Sendable Protocols**: `EliteServiceProtocol` completion handlers are now marked with `@Sendable` to safely cross XPC boundaries.
- **Safe Capture**: Capturing state in `Task` blocks now uses explicit capture lists (e.g., `[input, parameters]`) to prevent data races.
- **Non-isolated Service**: `EliteService` is non-isolated to comply with `NSXPCListenerDelegate`, delegating state-heavy operations to the `@MainActor` isolated `Orchestrator`.

## Performance Telemetry
v3-Native `InferenceActor` provides real-time performance data:
- **Tokens Per Second (TPS)**: Extracted from `Generation.info`.
- **Latency**: Measured from start to finish of the `AsyncStream`.
- **Self-Healing**: `AutoRecoveryEngine` can now clear KV caches and reduce context windows using the native v3 `clearCache()` and `setNextRequestConfig()` methods.

## CLI & Daemon Synchronization
The `elite` CLI tool and `EliteService` are synchronized via the **UNO Binary-Native Highway**:
- **Binary Signaling**: Tool calls and responses are passed as binary data (PropertyList/Data) over XPC.
- **Zero-Copy Performance**: Leveraging MLX's unified memory for zero-copy handoffs where applicable.

---
*Documented on 2026-05-02 as part of the v7.1 "Native Sovereign" Technical Finalization.*
