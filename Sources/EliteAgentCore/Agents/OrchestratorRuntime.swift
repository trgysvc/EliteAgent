import Foundation
import Combine

public actor OrchestratorRuntime {
    private let toolRegistry: ToolRegistry
    private let workspaceManager = WorkspaceManager.shared
    
    private let planner: PlannerAgent
    private let memory: MemoryAgent
    private let cloudProvider: CloudProvider
    private let localProvider: MLXProvider?
    private let contextManager: DynamicContextManager
    private let bus: SignalBus
    private var emergencyBuffer: [Signal] = []
    
    private var onStepUpdate: (@Sendable (TaskStep) -> Void)?
    private var onStatusUpdate: (@Sendable (AgentStatus) -> Void)?
    
    public func setStepUpdateHandler(_ handler: @Sendable @escaping (TaskStep) -> Void) {
        self.onStepUpdate = handler
    }

    public func setStatusUpdateHandler(_ handler: @Sendable @escaping (AgentStatus) -> Void) {
        self.onStatusUpdate = handler
    }
    private var onTokenUpdate: (@Sendable (TokenCount) -> Void)?
    
    public init(planner: PlannerAgent, memory: MemoryAgent, cloudProvider: CloudProvider, localProvider: MLXProvider? = nil, toolRegistry: ToolRegistry, bus: SignalBus) {
        self.planner = planner
        self.memory = memory
        self.cloudProvider = cloudProvider
        self.localProvider = localProvider
        self.toolRegistry = toolRegistry
        self.bus = bus
        self.contextManager = DynamicContextManager(maxTokens: cloudProvider.maxContextTokens, provider: cloudProvider)
    }
    
    public func setTokenUpdateHandler(_ handler: @Sendable @escaping (TokenCount) -> Void) async {
        self.onTokenUpdate = handler
    }
    
    public func executeTask(prompt: String, session: Session, complexity: Int = 3) async throws {
        await session.updateStatus(.thinking)
        onStatusUpdate?(.working)
        
        // Sound Architect: Dampen background audio (Focus Mode check)
        if await AppSettings.shared.isQuietModeEnabled {
            await AudioArchitect.shared.dampen()
        }
        
        // 1. Cognitive Simulation (Internal Monologue)
        let ragContext = await memory.retrieveRelevantExperiences(query: prompt)
        onStepUpdate?(TaskStep(name: "Simulating strategies...", status: "thinking", latency: "...", depth: session.recursionDepth))
        
        if let strategy = try? await InternalMonologueActor.shared.simulate(task: prompt, context: ragContext, provider: cloudProvider) {
            onStepUpdate?(TaskStep(name: "Strategy: \(strategy.name)", status: "done", latency: "ANE", depth: session.recursionDepth, thought: "Plan: \(strategy.plan)\nRisk: \(strategy.risk)"))
        }

        await contextManager.addMessage(Message(role: "user", content: prompt))
        var isRunning = true
        
        // Subscribe to emergency channel
        let (emergencyStream, _) = await bus.subscribe(for: .orchestrator)
        let signalingTask = Task { [weak self] in
            for await signal in emergencyStream {
                await self?.pushEmergency(signal)
            }
        }
        defer { signalingTask.cancel() }
        
        while isRunning {
            // 0. Hardware Protection Reflex (Emergency Priority)
            if let emergency = popEmergency() {
                onStepUpdate?(TaskStep(name: "⚠️ EMERGENCY: \(emergency.name)", status: "critical", latency: "ANE", thought: "Hardware reflex triggered. Priority: \(emergency.priority)"))
                try await handleEmergency(emergency, session: session)
            }

            // 0b. Check for Task Cancellation
            if Task.isCancelled {
                isRunning = false
                await session.updateStatus(.failed)
                return
            }
            
            // 1. Check Recursion Depth
            if await session.isRecursionLimitReached() {
                await session.updateStatus(.failed)
                throw NSError(domain: "Orchestrator", code: 4, userInfo: [NSLocalizedDescriptionKey: "Max recursion depth reached"])
            }
            
            // 2. RAG Retrieval
            let ragContext = await memory.retrieveRelevantExperiences(query: prompt)
            
            // 3. Get Next Move from Planner
            let systemPrompt = await PlannerTemplate.generateAgenticPrompt(session: session, ragContext: ragContext)
            
            // Memory Compression: Check if context is too large
            try? await contextManager.compress(sessionID: session.id.uuidString)
            
            let request = CompletionRequest(
                taskID: session.id.uuidString,
                systemPrompt: systemPrompt,
                messages: await contextManager.getMessages(),
                maxTokens: 2000,
                sensitivityLevel: .public,
                complexity: 3
            )
            
            // Hybrid Reasoning: Route between Local and Cloud (Offline-First Strategy)
            let isLocalReady = await ModelSetupManager.shared.isModelReady
            let providerToUse: LLMProvider = (localProvider != nil && isLocalReady) ? localProvider! : cloudProvider
            
            let response = try await providerToUse.complete(request)
            
            // TRACE: Log the raw response for debugging Stochastic Skips / Hallucinations
            print("[RAW LLM RESPONSE]:\n\(response.content)\n-------------------")
            
            await contextManager.addMessage(Message(role: "assistant", content: response.content))
            await session.addTokenUsage(response.tokensUsed)
            onTokenUpdate?(response.tokensUsed)
            
            // Record to MetricsStore
            await MetricsStore.shared.update(
                modelID: cloudProvider.modelName, 
                promptTokens: response.tokensUsed.prompt, 
                completionTokens: response.tokensUsed.completion, 
                cost: response.costUSD
            )
            
            // 3. Parse Thinking vs Action
            let result = ThinkingParser.parse(response.content)
            
            // Log thinking
            if let think = result.thinking {
                let depth = session.recursionDepth
                onStepUpdate?(TaskStep(name: "Reasoning...", status: "thinking", latency: "...", depth: depth, thought: think))
            }
            
            // 4. Determine Action: PRIORITIZE tool call in full content or final answer
            let toolCallCandidate = parseToolCall(response.content) ?? parseToolCall(result.finalAnswer)
            
            if let toolCall = toolCallCandidate {
                let depth = session.recursionDepth
                print("[ORCHESTRATOR] Verified Tool Call: \(toolCall.name) with params: \(toolCall.params)")
                onStepUpdate?(TaskStep(name: "Tool: \(toolCall.name)", status: "executing", latency: "...", depth: depth))
                
                await session.updateStatus(.executing)
                
                if let tool = toolRegistry.getTool(named: toolCall.name) {
                    do {
                        // Safety Check (LogicGate)
                        if toolCall.name == "shell_exec", let cmd = toolCall.params["command"]?.value as? String {
                            let risk = LogicGate.shared.check(command: cmd)
                            if risk.isDangerous {
                                throw ToolError.executionError("Safety Block: \(risk.reason ?? "Dangerous command detected")")
                            }
                        }
                        
                        let toolResult = try await tool.execute(params: toolCall.params, session: session)
                        await contextManager.addMessage(Message(role: "user", content: "Tool [\(toolCall.name)] returned: \(toolResult)"))
                    } catch {
                        // Self-Healing Logic (Autonomous Recovery)
                        if let strategy = await SelfHealingEngine.shared.analyze(error: error.localizedDescription, tool: toolCall.name),
                           await SelfHealingEngine.shared.canRetry(error: error.localizedDescription) {
                            
                            onStepUpdate?(TaskStep(name: "Healing: \(strategy.name)", status: "healing", latency: "Retry", depth: session.recursionDepth, thought: strategy.description))
                            await session.updateStatus(.healing)
                            onStatusUpdate?(.healing)
                            await session.recordHealingAttempt()
                            await SelfHealingEngine.shared.recordRetry(error: error.localizedDescription)
                            
                            // Execute healing command if it exists
                            if let fixCmd = strategy.command {
                                _ = try? await (toolRegistry.getTool(named: "shell_exec")?.execute(params: ["command": AnyCodable(fixCmd)], session: session))
                            }
                            
                            await contextManager.addMessage(Message(role: "user", content: "Tool [\(toolCall.name)] failed but I applied healing: \(strategy.name). Retrying..."))
                            onStatusUpdate?(.working)
                        } else {
                            await contextManager.addMessage(Message(role: "user", content: "Tool [\(toolCall.name)] failed with error: \(error.localizedDescription)"))
                        }
                    }
                } else {
                    await contextManager.addMessage(Message(role: "user", content: "Tool [\(toolCall.name)] not found in registry."))
                }
            } else {
                // No tool call found, assume it's the final answer
                await session.updateStatus(.finished, finalAnswer: result.finalAnswer)
                isRunning = false
                
                // 5. Store Experience (Cumulative Intelligence)
                await memory.storeExperience(task: prompt, solution: result.finalAnswer)
                
                // Sound Architect: Restore background audio (Focus Mode check)
                if await AppSettings.shared.isQuietModeEnabled {
                    await AudioArchitect.shared.restore()
                }
                
                print("[FINAL]: \(result.finalAnswer)")
            }
        }
    }
    
    private func parseToolCall(_ text: String) -> (name: String, params: [String: AnyCodable])? {
        // 1. Extract JSON block (strip markdown/tags)
        let cleaned = text.replacingOccurrences(of: "<final>", with: "")
                          .replacingOccurrences(of: "</final>", with: "")
                          .trimmingCharacters(in: .whitespacesAndNewlines)
        
        guard let start = cleaned.firstIndex(of: "{") else { return nil }
        // Scan for the most balanced JSON-like suffix
        let rawJson = String(cleaned[start...])
        
        // 2. Sanitize: Escape literal newlines ONLY within double-quoted strings
        var sanitizedJson = sanitizeJSONResilient(rawJson)
        
        // 3. Auto-Balancing: AI often forgets closing braces. Let's fix it.
        sanitizedJson = balanceBraces(sanitizedJson)
        
        // 4. Parse using JSONSerialization
        guard let data = sanitizedJson.data(using: .utf8),
              let jsonObject = (try? JSONSerialization.jsonObject(with: data) as? [String: Any]) ?? findBestJSONMatch(sanitizedJson) else {
            return nil
        }
        
        // 5. Map to ToolCall structure
        guard let name = jsonObject["tool"] as? String,
              let rawParams = jsonObject["params"] as? [String: Any] else {
            return nil
        }
        
        let params = rawParams.mapValues { AnyCodable($0) }
        return (name, params)
    }

    /// Internal Helper: If JSONSerialization fails, try to aggressively find a { ... } block
    private func findBestJSONMatch(_ input: String) -> [String: Any]? {
        // Find the last possible '}' that results in a valid parse
        var temp = input
        while temp.contains("}") {
            if let data = temp.data(using: .utf8),
               let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                return obj
            }
            if let lastIdx = temp.lastIndex(of: "}") {
                temp = String(temp[..<lastIdx])
            } else { break }
        }
        return nil
    }

    /// Auto-Balance: Appends missing closing braces to fix malformed AI output.
    private func balanceBraces(_ input: String) -> String {
        var openCount = 0
        var insideString = false
        var escaped = false
        
        for char in input {
            if char == "\"" && !escaped {
                insideString.toggle()
            }
            
            if !insideString {
                if char == "{" { openCount += 1 }
                else if char == "}" { openCount -= 1 }
            }
            
            if char == "\\" && !escaped {
                escaped = true
            } else {
                escaped = false
            }
        }
        
        var fixed = input
        if openCount > 0 {
            // Need to close strings first if the AI cut off mid-string
            if insideString { fixed += "\"" }
            // Add missing braces
            for _ in 0..<openCount {
                fixed += "}"
            }
        }
        return fixed
    }

    /// Resilient Sanitizer: Correctly escapes newlines only within strings, handling escaped quotes.
    private func sanitizeJSONResilient(_ input: String) -> String {
        // Regex to match JSON strings: " (anything except quote or backslash, or escaped any-char)* "
        let pattern = #""(?:[^"\\]|\\.)*""#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.dotMatchesLineSeparators]) else {
            return input
        }
        
        let nsString = input as NSString
        var result = ""
        var lastOffset = 0
        
        let matches = regex.matches(in: input, options: [], range: NSRange(location: 0, length: nsString.length))
        
        for match in matches {
            // Add the non-string part (JSON structure)
            result += nsString.substring(with: NSRange(location: lastOffset, length: match.range.location - lastOffset))
            
            // Extract the string part and escape its internal newlines
            var stringPart = nsString.substring(with: match.range)
            stringPart = stringPart.replacingOccurrences(of: "\n", with: "\\n")
            stringPart = stringPart.replacingOccurrences(of: "\r", with: "\\r")
            stringPart = stringPart.replacingOccurrences(of: "\t", with: "\\t")
            
            result += stringPart
            lastOffset = match.range.location + match.range.length
        }
        
        // Add the remaining part
        if lastOffset < nsString.length {
            result += nsString.substring(from: lastOffset)
        }
        
        return result
    }

    private func pushEmergency(_ signal: Signal) {
        emergencyBuffer.append(signal)
    }
    
    private func popEmergency() -> Signal? {
        guard !emergencyBuffer.isEmpty else { return nil }
        return emergencyBuffer.removeFirst()
    }
    
    private func handleEmergency(_ signal: Signal, session: Session) async throws {
        // Logic for handling critical hardware states
        if signal.name == "THERMAL_CRITICAL" {
            onStepUpdate?(TaskStep(name: "Thermal Throttling", status: "throttled", latency: "0ms", thought: "Reducing LLM complexity to protect M-series silicon."))
            // In a real scenario, we might switch to a smaller model or pause
            try await Task.sleep(nanoseconds: 2_000_000_000) // Cooling period
        }
    }
}
