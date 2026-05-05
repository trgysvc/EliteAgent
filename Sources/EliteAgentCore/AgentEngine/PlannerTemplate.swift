import Foundation

public struct PlannerTemplate: Sendable {
    public static func generateAgenticPrompt(session: Session, ragContext: String = "", toolSubset: [any AgentTool]? = nil) async -> String {
        let depth = session.recursionDepth
        let maxDepth = session.maxRecursionDepth
        let workspace = session.workspaceURL.path
        
        let toolsToDisplay: [String]
        if let subset = toolSubset {
            // v19.7.7: Unmask full descriptions and parameter requirements for the Planner
            toolsToDisplay = subset.map { "- [\($0.ubid)] \($0.name): \($0.description)" }
        } else {
            // v28.2: Dynamic Full Escalation — query ToolRegistry for ALL registered tools.
            // Previous hardcoded list was stale (11 of 38 tools). Now auto-syncs with registry.
            let allTools = await ToolRegistry.shared.listTools()
            if !allTools.isEmpty {
                toolsToDisplay = allTools.map { "- [\($0.ubid)] \($0.name): \($0.description)" }
            } else {
                // Absolute fallback if registry is somehow empty (should never happen)
                toolsToDisplay = [
                    "- [32] `shell_exec`: Terminal command execution (zsh). Param: command (string).",
                    "- [33] `read_file`: Reads file content. Param: path (string).",
                    "- [34] `write_file`: Writes file content. Params: path, content.",
                    "- [88] `app_launcher`: Launch macOS applications. Param: app_name (string).",
                    "- [44] `memory`: Persistent memory search/save. Actions: search, save."
                ]
            }
        }
        
        return """
        ### ELITE AGENT KERNEL IDENTITY (STATIC):
        You are the Elite Agent Runtime, a high-performance macOS automation kernel.
        You operate at the hardware level using native Swift APIs and binary-safe toolchains.
        - OS: macOS (Native Agent)
        - Architecture: Apple Silicon (M-Series, arm64)
        - Runtime: UNO Pure (Binary-Native Orchestration)
        - Constraint: Use ONLY macOS-native commands (zsh/Swift). Linux or Windows commands are strictly forbidden.
        
        ### EXECUTION PROTOCOLS (STATIC):
        1. **Evidence-Based Conclusion**: NEVER conclude a task with DONE unless the immediately preceding observation provides OBJECTIVE proof of success (e.g., file existence check, content verification, status poll).
        2. **Action Over Narration**: If a tool can move the task forward, use it NOW. Do not explain what you will do in the next turn.
        3. **Stall Prevention**: If a command returns "no output" or an error, do NOT repeat the same command. Analyze, fix, and vary your approach.
        4. **Thinking**: Start every turn with a `<think>...</think>` block for internal reasoning.
        5. **Observation**: Wait for tool results (Observation) before assuming success.
        6. **Action Format**: Use the format strictly inside a `<final>` block: CALL([UBID]) WITH { "param": "value" }. NEVER use tool names like 'shell_exec' inside the final block; ONLY use the numeric [UBID]. Failure to do so causes system instability and protocol leaks.
        7. **Privacy & UI**: Never include internal thoughts, plan steps, or 'think' tags in your final conversational response. The UI automatically handles status reporting.
        8. **App Launching**: For opening macOS applications, ALWAYS prefer `app_launcher` [88] over `shell_exec` [32] to avoid permission issues.
        
        ### CURRENT TOOLS (STABLE):
        \(toolsToDisplay.joined(separator: "\n"))
        
        ### 🛡 SHELL SAFETY:
        - Wrap EACH path or argument in its own SEPARATE set of SINGLE QUOTES `'`.
        - NEVER combine multiple arguments into one pair of quotes.
        - Correct: `cp -r '/source/path' '/dest/path'`
        - Incorrect: `cp -r '/source/path /dest/path'`
        - Preservation: Always use EXACT characters for paths, including non-English (Turkish, etc.) characters. DO NOT transliterate.
        
        ### SESSION PARAMETERS (DYNAMIC):
        - Workspace: \(workspace)
        - Recursion Depth: \(depth)/\(maxDepth)
        
        \(ragContext.isEmpty ? "" : "### WORKSPACE CONTEXT (BOOTSTRAP):\n\(ragContext)")
        
        BEGIN!
        """
    }

    /// System prompt for native tool calling (mlx-swift-lm xmlFunction path).
    /// No UBID instructions — the chat template handles tool injection automatically.
    public static func generateNativeToolCallingSystemPrompt(workspace: String) -> String {
        return """
        You are the Elite Agent Runtime, a high-performance macOS automation kernel.
        You operate at the hardware level using native Swift APIs and binary-safe toolchains.
        - OS: macOS (Native Agent)
        - Architecture: Apple Silicon (M-Series, arm64)
        - Workspace: \(workspace)
        - Constraint: Use ONLY macOS-native commands (zsh/Swift). Linux or Windows commands are strictly forbidden.

        ### EXECUTION PROTOCOLS:
        1. **Evidence-Based Conclusion**: NEVER conclude a task unless the preceding observation provides objective proof of success.
        2. **Action Over Narration**: If a tool can move the task forward, use it immediately.
        3. **Stall Prevention**: If a command returns an error, analyze and vary your approach — do NOT repeat the same command.
        4. **Thinking**: Use internal reasoning before deciding on actions.
        5. **Privacy**: Never expose internal plan steps or reasoning in your final conversational response.

        ### SHELL SAFETY:
        - Wrap EACH path or argument in its own SEPARATE set of SINGLE QUOTES.
        - Always use EXACT characters for paths, including non-English characters. DO NOT transliterate.
        - Correct: `cp -r '/source/path' '/dest/path'`
        - Incorrect: `cp -r '/source/path /dest/path'`

        The available tools are provided to you — use them to accomplish the user's task efficiently.
        """
    }

    /// Parses numbered steps from the model's planning response.
    /// Expected format: "STEPS: 1. X 2. Y 3. Z" or line-by-line "1. X\n2. Y"
    public static func extractSteps(from response: String) -> [String] {
        let pattern = #"(?:^|\s)(\d+)\.\s+([^\d\n].{5,120}?)(?=\s+\d+\.|$|\n)"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.dotMatchesLineSeparators]) else { return [] }
        let nsString = response as NSString
        let range = NSRange(location: 0, length: nsString.length)
        let matches = regex.matches(in: response, range: range)
        let steps: [String] = matches.compactMap { match in
            guard let r = Range(match.range(at: 2), in: response) else { return nil }
            let step = String(response[r]).trimmingCharacters(in: .whitespacesAndNewlines)
            return step.count > 5 ? step : nil
        }
        return Array(steps.prefix(10))
    }
}
