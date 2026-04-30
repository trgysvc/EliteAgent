# Contributing to EliteAgent

Thank you for your interest in contributing to EliteAgent! We maintain strict architectural standards to ensure the system remains the fastest and most secure native agent on macOS.

## 🏗 Architectural Principles (UNO)

All contributions must adhere to the **Unified Native Orchestration (UNO)** protocol:

1. **No JSON Internally**: Never use `JSONEncoder`, `JSONDecoder`, or string-based JSON payloads for communication between actors or tools. Use `Foundation.PropertyListEncoder` (binary format) or raw byte buffers.
2. **Native-First**: Avoid external dependencies. If a feature can be implemented using Apple's native frameworks (AppKit, SwiftUI, XPC, Security, etc.), it MUST be.
3. **Hardware-Aware**: Code should be optimized for Apple Silicon Unified Memory Architecture (UMA). Avoid redundant data copies.
4. **Compile-Time Safety**: Use `Distributed Actors` for cross-boundary communication to ensure type safety at compile time.

## 🛠 Adding New Tools

To add a tool to the EliteAgent Master Registry:

1. **Implement `AgentTool`**: Create a new Swift file in `Sources/EliteAgentCore/ToolEngine/Tools/`.
2. **Assign a UBID**: Assign a Unique Binary ID (Int128). Check the existing registry in `Orchestrator.swift` to avoid collisions.
3. **Handle Parameters**: Use `AnyCodable` for parameters and ensure they are property-list compatible.
4. **Register**: Add your tool to the registration block in `Orchestrator.swift`.

### Example Tool Template:
```swift
public struct MyNewTool: AgentTool, Sendable {
    public let name = "my_tool"
    public let summary = "Brief summary for LLM."
    public let description = "Detailed instructions for LLM triggering."
    public let ubid: Int128 = 123 // Choose a unique ID
    
    public func execute(params: [String: AnyCodable], session: Session) async throws(AgentToolError) -> String {
        // Implementation here
        return "Result string"
    }
}
```

## 🧪 Testing Requirements

We maintain a **Zero Regression** policy.

- **Unit Tests**: Every new tool must have a corresponding test in `Tests/EliteAgentTests/`.
- **Integration**: Ensure the tool respects the `Workspace Isolation` boundary if enabled.
- **Marathon Tests**: For complex orchestration tools, add a new workflow case to `EliteMarathonTests.swift`.

Run the full suite before submitting:
```bash
swift test
```

## 🛡 Security Standards

- **Path Hardening**: Always use `PathConfiguration.shared.workspaceURL` as the root. Never allow arbitrary file access outside the sandbox.
- **Privacy**: No data should be transmitted to external servers without explicit user authorization via the `SecuritySentinel` (biometrics).
- **Audit Logs**: Use `AgentLogger.logAudit` for all tool executions to maintain a forensic trail.

---

*EliteAgent is a high-performance machine. Keep it clean, keep it native, and keep it fast.*
