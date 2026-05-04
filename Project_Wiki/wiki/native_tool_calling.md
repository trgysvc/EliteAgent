# Native Tool Calling — Implementation Guide (v8.0)

**Implemented:** 2026-05-04  
**Status:** Production-ready

---

## Overview

EliteAgent v8.0 implements native tool calling via the mlx-swift-lm `xmlFunction` format. Qwen 3.5 (and compatible models) emit `<tool_call>` blocks directly; the framework parses them into `Generation.toolCall` events, which are converted to `InferenceChunk.toolCall` and dispatched by `OrchestratorRuntime`.

This replaces the legacy UBID-string parsing path (`CALL([UBID]) WITH {...}`) for local model inference.

---

## End-to-End Flow

```
1. OrchestratorRuntime.handlePlanning()
   └─ builds ToolSpec array via buildToolSpecs(for: tools)
   └─ creates CompletionRequest(tools: toolSpecs, complexity: 3)
   └─ calls MLXProvider.complete(request)

2. MLXProvider.complete()
   └─ passes request.tools to InferenceActor.generate(tools:)
   └─ enableThinking = (request.complexity > 1) = true for planning

3. InferenceActor.generate()
   └─ UserInput(messages: mlxMessages, tools: tools, additionalContext: additionalContext)
   └─ container.prepare(input: userInput) → LMInput
   └─ mlx-swift-lm injects tool schemas into Qwen 3.5's chat template (xmlFunction format)
   └─ Qwen 3.5 generates: <tool_call>{"name": "shell_exec", "arguments": {...}}</tool_call>
   └─ Framework parses → Generation.toolCall(ToolCall)
   └─ InferenceActor yields: InferenceChunk.toolCall(name:, arguments:)

4. MLXProvider.complete()
   └─ collects: collectedToolCalls.append(ToolCall(tool: name, ubid: nil, params: arguments))
   └─ returns CompletionResponse(toolCalls: collectedToolCalls)

5. OrchestratorRuntime.handleExecution()
   └─ detects response.toolCalls != nil
   └─ ToolRegistry.shared.getTool(named: toolCall.tool)  // name-based lookup, no UBID needed
   └─ tool.execute(params: toolCall.params, session: session)
   └─ yields observation back to next planning cycle
```

---

## Key Files

| File | Role |
|---|---|
| `InferenceActor.swift` | `generate(tools:enableThinking:)` — UserInput with tools, yields `.toolCall` chunks |
| `MLXProvider.swift` | `complete()` — collects tool calls, returns in `CompletionResponse.toolCalls` |
| `OrchestratorRuntime.swift` | `handlePlanning()` builds ToolSpecs; `handleExecution()` dispatches via `ToolRegistry` |
| `PlannerTemplate.swift` | `generateNativeToolCallingSystemPrompt()` — minimal system prompt for local model |
| `LLMTypes.swift` | `InferenceChunk.toolCall(name:arguments:)` — new case for native tool calls |

---

## ToolSpec Format

ToolSpecs are `[[String: any Sendable]]` in OpenAI function-calling format:

```swift
func toolSpec(_ name: String, _ description: String, _ properties: [String: [String: any Sendable]]) -> [String: any Sendable] {
    return [
        "type": "function",
        "function": [
            "name": name,
            "description": description,
            "parameters": [
                "type": "object",
                "properties": properties,
                "required": Array(properties.keys)
            ] as [String: any Sendable]
        ] as [String: any Sendable]
    ]
}
```

mlx-swift-lm auto-detects `model_type = "qwen3_5"` from `config.json` and uses xmlFunction format.

---

## Think Block Handling

Qwen 3.5 generates `<think>...</think>` blocks before answering. `MLXProvider` handles this via:

```swift
static func extractThinkBlock(from text: String) -> (think: String, response: String)
```

- **Format A:** `<think>...</think>` XML tags → splits at `</think>`, returns clean response
- **Format B:** "Thinking Process:" plain text prefix → extracts answer from last conclusion marker

The `thinkBlock` is stored in `CompletionResponse.thinkBlock` (for logging/planning use). The `content` field contains only the clean user-facing response.

---

## Intent Classification: When Native Tool Calling Activates

`OrchestratorRuntime.classifyIntent()` runs with `enableThinking=false, maxTokens=64` to quickly determine:

- `chat` → `handleChatting()` — direct response, no tools, minimal system prompt
- `task` → `handlePlanning()` → `handleExecution()` — full native tool calling path

For local model (Titan Engine):
- System prompt: `PlannerTemplate.generateNativeToolCallingSystemPrompt(workspace:)` — no UBID instructions
- Tools: `buildToolSpecs(for: session.activeTools)` — all registered tools as ToolSpecs
- `complexity = 3` → `enableThinking = true` → model reasons before tool calls

For cloud model (OpenRouter):
- Falls back to legacy `generateAgenticPrompt()` with UBID instructions and `<final>` block format

---

## Chat Latency Optimization

The critical fix for chat latency was disabling the think block:

```swift
// InferenceActor.generate()
let additionalContext: [String: any Sendable]? = enableThinking ? nil : ["enable_thinking": false]
```

| Mode | Think block | ~Tokens | ~Time at 13 TPS |
|---|---|---|---|
| `enableThinking = true` | Full `<think>` block | 800+ | ~62s |
| `enableThinking = false` | Skipped | ~50 | ~4s |

`enable_thinking: false` is the official mlx-swift-lm API for Qwen 3.5. It suppresses `<think>` generation entirely rather than just stripping the output.

---

## OrchestratorRuntime: Native vs. Legacy Dispatch

```swift
// In handleExecution():
if let toolCalls = lastPlanningResponse?.toolCalls, !toolCalls.isEmpty {
    // NATIVE PATH: mlx-swift-lm parsed tool calls
    for toolCall in toolCalls {
        if let tool = await ToolRegistry.shared.getTool(named: toolCall.tool) {
            let result = try await tool.execute(params: toolCall.params, session: session)
            // ...
        }
    }
} else {
    // LEGACY PATH: ThinkParser extracts CALL([UBID]) WITH {...}
    let callInstruction = ThinkParser.extractCallInstruction(from: response.content)
    // ...
}
```

The native path requires no UBID — `ToolRegistry.getTool(named:)` does name-based lookup.

---

## UNO Rule Compliance

Native tool calling uses `[[String: any Sendable]]` (ToolSpec format) for tool schemas. This is NOT a JSON violation because:
1. It's an in-memory Swift dictionary, not encoded/decoded via JSONEncoder/JSONDecoder
2. mlx-swift-lm's type alias `ToolSpec = [String: any Sendable]` is purely an in-process data structure
3. The binary transport layer (UNO/XPC) receives typed `CompletionResponse`, not raw dictionaries

The only JSON touching in this flow is `UNOExternalBridge` when cloud responses arrive — correct.
