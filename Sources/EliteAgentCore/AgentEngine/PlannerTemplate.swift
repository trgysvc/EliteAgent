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
            // Default to Master Toolset if no subset provided (Full Escalation Mode)
            toolsToDisplay = [
                "- [18] `music_dna`: Professional audio/music analysis (LUFS, BPM, MFCC). Param: path (string).",
                "- [32] `shell_exec`: Terminal command execution (zsh). Param: command (string).",
                "- [33] `read_file`: Reads file content using native Swift APIs. Param: path (string).",
                "- [34] `write_file`: Writes file content using native Swift APIs (MANDATORY). Params: path, content.",
                "- [37] `messenger`: Sends iMessage/WhatsApp messages (Native).",
                "- [40] `safari_automation`: Safari automation and Google search (NATIVE).",
                "- [45] `web_search`: Performs Google search (WebFetch). Param: query (string).",
                "- [81] `get_weather`: Native weather telemetry. Param: location (string), day (optional string).",
                "- [85] `id3_processor`: Recursive Native Music Processor (ID3 metadata, cover art, clean rename). Param: directory (string), custom_tags (dictionary, optional - e.g. {'TPE1': 'Artist', 'TALB': 'Album'})."
            ]
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
        6. **Action Format**: Use the format strictly inside a `<final>` block: CALL([UBID]) WITH { "param": "value" }.
        7. **Echo Guard**: Do NOT repeat data already shown in an observation. If the observation contains the answer, output ONLY `<final>DONE</final>`.
        
        ### CURRENT TOOLS (STABLE):
        \(toolsToDisplay.joined(separator: "\n"))
        - [30] `visual_audit`: Analyzes screen windows, text, and UI elements.
        
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
