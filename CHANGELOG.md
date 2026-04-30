# CHANGELOG

All notable changes to EliteAgent will be documented in this file.

## [7.0.0] - 2026-05-01
### "Native Sovereign" Release

This major release marks the transition of EliteAgent into a production-ready, hardware-native autonomous system. The architecture has been completely overhauled to prioritize performance, privacy, and Apple Silicon optimization.

### Added
- **UNO (Unified Native Orchestration)**: A binary-native communication highway using `Distributed Actors` and `SharedMemoryPool`.
- **Proactive Memory Pressure Monitor**: Hardware-aware watchdog that manages UMA pressure (M1-M4 support).
- **Native Safari Automation**: High-fidelity control via `AXUIElement` and `SafariJSBridge`.
- **Blender Headless Automation**: Full `bpy` Python API orchestration for 3D workflows.
- **Elite Marathon E2E Suite**: 10 comprehensive end-to-end workflow tests for orchestration validation.
- **Xcode Autonomous Builder**: New `XcodeTool` for building and debugging Swift projects without user intervention.

### Changed
- **Binary-Only Protocol**: Removed all internal JSON usage in favor of PropertyLists and memory mapping.
- **MLX-Native Tokenization**: Replaced `swift-transformers` with a custom `BPETokenizer` running on GPU/Neural Engine.
- **Security Hardening**: Standardized workspace root at `~/Workspaces/EliteAgent` with optional biometric isolation.
- **Registry Overhaul**: All tools now use Unique Binary IDs (UBIDs) for deterministic triggering.

### Removed
- **JSON-RPC Internals**: Eliminated string-based IPC overhead.
- **Chrome-MCP Dependency**: Native Safari automation replaces the need for external browser servers.
- **Legacy Path Resolvers**: Transitioned all storage to `Application Support` and standardized workspace paths.

---

## 🛠 Migration Guide: v6.x to v7.0

### 1. Configuration Move
EliteAgent v7.0 uses a centralized `vault.plist` for all secrets and MCP configurations.
- **Old Path**: `~/.eliteagent/config.json`
- **New Path**: `~/Library/Application Support/EliteAgent/vault.plist`
- *Action*: Use the `scripts/setup.sh` to generate a new template and migrate your API keys.

### 2. Workspace Standardization
The agent now enforces a strict workspace boundary for security.
- **Standard Path**: `~/Workspaces/EliteAgent`
- *Action*: Move your active project folders into the new standardized workspace root.

### 3. Tool Calling Format
If you have custom subagents or prompts, update them to use **Numeric UBIDs** inside `<final>CALL(ID) WITH {params}</final>` blocks instead of string tool names.

### 4. Dependency Cleanup
Run `swift package update` and `swift package purge-cache`. The `swift-transformers` dependency is no longer required and should be removed from your local environment if present.
