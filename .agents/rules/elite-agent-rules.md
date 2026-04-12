---
trigger: always_on
---

# EliteAgent – Workspace Rules

## Language & Standards

- All code is written in **Swift 6** with strict concurrency (`swift-6` language mode).
- Follow the [Swift API Design Guidelines](https://swift.org/documentation/api-design-guidelines/).
- Language reference: [The Swift Programming Language](https://docs.swift.org).

## Architecture: UNO (Unified Native Orchestration)

UNO replaces text-based messaging with a binary-native, compile-time-safe communication highway
built on Distributed Actors and XPC.

- Primary concurrency model is **Distributed Actors** (Swift 5.7+). Always prefer `distributed actor`
  over classes for cross-boundary components.
- Use **XPC Services** for all inter-process communication. Reference:
  [Creating XPC Services](https://developer.apple.com/documentation/xpc).
- Actor boundaries must be explicit. Never share mutable state across actors without
  `async/await` or `Sendable` conformance.

### UNO: No JSON — Binary Only

- **Never use JSON** anywhere in the codebase. No `JSONEncoder`, `JSONDecoder`, `JSONSerialization`,
  or any text-based serialization.
- All data crossing Actor or XPC boundaries travels as **binary** (`Data` / `NSSecureCoding`).
  Use `Foundation.PropertyListEncoder(outputFormat: .binary)` or raw byte buffers.
- XPC transfers use **memory mapping**, not string payloads. Data is never "stringified" —
  it is passed in its original binary form (e.g., `Float`, `Int` as byte sequences).
- Tool calls are registered at launch as **Binary Signatures** (Lookup Table).
  When the LLM triggers a tool, it emits a **Unique Binary ID + typed Swift parameters**
  — not a text string. The host app routes this directly to the Swift function with zero
  string manipulation.

### UNO: Compile-Time Safety

- All inter-component communication must be type-safe at **compile time**, not runtime.
- Distributed Actor method calls enforce parameter types and return types via the Swift compiler.
  If it doesn't compile, it doesn't ship.
- No "duck typing", `Any`, or untyped dictionaries across boundaries.

### UNO: Logit Filtering (Grammar Constraints)

- The LLM must never produce free-form text for tool invocations.
- In `InferenceActor`, apply **Grammar Constraints** via MLX LogitProcessor to restrict
  token generation to valid Swift Enum values or Binary IDs only.
- Parsing errors are architecturally impossible by design — the model is physically
  constrained to valid output format.

## MLX – Local Inference Engine

- Local inference is handled via [mlx-swift](https://github.com/ml-explore/mlx-swift).
- LLM loading patterns (Llama, Mistral, etc.):
  [mlx-swift-examples](https://github.com/ml-explore/mlx-swift-examples).
- Full API reference (unified memory, GPU ops): [MLX Docs](https://ml-explore.github.io/mlx/).

### MLX Rules

- **Unified Memory**: Never copy data between CPU/GPU explicitly. Let MLX manage unified memory.
  Avoid `Array` → tensor conversions inside hot paths.
- **Quantization**: Default to 4-bit quantization for local models unless fp16 is explicitly required.
- **Logit Processors**: Grammar constraints in `InferenceActor` must use MLX LogitProcessor API —
  never post-processing string manipulation.

## Apple Frameworks & APIs

- Primary reference: [Apple Developer Documentation](https://developer.apple.com/documentation).
- XPC: [Creating XPC Services](https://developer.apple.com/documentation/xpc).
- App Intents: [App Intents Framework](https://developer.apple.com/documentation/appintents).
- Xcode: [Xcode Documentation](https://developer.apple.com/documentation/xcode).
- Always prefer native Apple APIs. **Zero external dependencies** beyond `mlx-swift`.

## Design & HIG

- All UI must conform to
  [Human Interface Guidelines](https://developer.apple.com/design/human-interface-guidelines/).
- Design resources: [Apple Design Resources](https://developer.apple.com/design/resources/).
- Target platform: **macOS-native only**. SwiftUI preferred.
  No AppKit fallbacks unless strictly required.

## Code Quality Rules

- No force unwrap (`!`) in production code. Use `guard let` or `if let`.
- All `async` functions must have explicit error handling (`throws` or `Result`).
- No `DispatchQueue`. All concurrency through Swift structured concurrency
  (`async/await`, `TaskGroup`, `Actor`).
- `@MainActor` must be explicitly annotated on all UI-touching code.

## Reference Index

| Topic | URL |
|---|---|
| Swift Language | https://docs.swift.org |
| API Design Guidelines | https://swift.org/documentation/api-design-guidelines/ |
| Apple Developer Docs | https://developer.apple.com/documentation |
| XPC Services | https://developer.apple.com/documentation/xpc |
| App Intents | https://developer.apple.com/documentation/appintents |
| MLX Swift | https://github.com/ml-explore/mlx-swift |
| MLX Swift Examples | https://github.com/ml-explore/mlx-swift-examples |
| MLX Full Docs | https://ml-explore.github.io/mlx/ |
| HIG | https://developer.apple.com/design/human-interface-guidelines/ |


## Developer Log & Documentation Maintenance

- After every completed task, append an entry to `DEVLOG.md` in the following format:

    ### [YYYY-MM-DD] — {Task Summary}
    **What changed:** {Brief description of the change}
    **Files modified:** {List of affected files}
    **Decision made:** {Any architectural or technical decision, if applicable}
    **Next:** {Follow-up task or open question, if any}

- If the task modifies behavior, architecture, or public-facing functionality, check the following files for sections that require updating:
  - `README.md` — feature list, usage instructions, architecture overview
  - `README_TR.md` — Turkish equivalent, if present
  - Any `PLAN.md`, `ROADMAP.md`, or `implementation_plan.md` relevant to the changed area

- Do not rewrite entire README files. Update only the sections directly affected by the current task.

- If a README section is outdated but the current task does not cover it, add a `<!-- TODO: update -->` comment inline and move on.

- DEVLOG entries are append-only. Never edit or delete previous entries.