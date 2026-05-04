import Foundation
import MLX
import MLXLLM

/// v31.3: Official v3-Native MLX Provider
/// Bridges the generic Completion API to the hardware-accelerated InferenceActor.
public actor MLXProvider: LocalLLMProvider {
    public static let shared = MLXProvider(providerID: .mlx)
    
    public nonisolated let providerID: ProviderID
    public nonisolated let providerType: ProviderType = .local
    public let capabilities: Set<Capability> = [.think, .code, .general]
    public let costPer1KTokens: Decimal = 0
    public let maxContextTokens: Int = 16384
    public private(set) var status: ProviderStatus = .ready
    
    public nonisolated var isLoaded: Bool { true }
    
    public init(providerID: ProviderID) {
        self.providerID = providerID
        self.status = .ready
    }
    
    public func healthCheck() async -> Bool {
        return await InferenceActor.shared.isModelLoaded
    }
    
    public func loadModel(_ modelName: String) async throws {
        self.status = .loading
        do {
            guard let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
                throw ModelError.unknown("Uygulama Destek dizini bulunamadı.")
            }
            let modelURL = appSupport.appendingPathComponent("EliteAgent/Models/\(modelName)")
            
            self.status = .priming
            try await InferenceActor.shared.loadModel(at: modelURL)
            self.status = .ready
        } catch {
            self.status = .error
            throw error
        }
    }
    
    public func unloadModel() async {
        await InferenceActor.shared.unloadModel()
        self.status = .idle
    }
    
    public func complete(_ request: CompletionRequest, useSafeMode: Bool) async throws -> CompletionResponse {
        let startTime = Date()
        let messages = request.messages.map { Message(role: $0.role, content: $0.content) }

        // enableThinking=false for chat/classification (no <think> block → faster responses).
        // enableThinking=true for planning/reasoning so the model can reason before tool calls.
        let enableThinking = request.complexity > 1

        let stream = try await InferenceActor.shared.generate(
            messages: messages,
            systemPrompt: request.systemPrompt,
            maxTokens: request.maxTokens,
            tools: request.tools,
            enableThinking: enableThinking
        )

        var fullContent = ""
        var firstTokenTime: Date?
        var finalMetrics: (prompt: Int, completion: Int, tps: Double)?
        var collectedToolCalls: [ToolCall] = []

        for await chunk in stream {
            switch chunk {
            case .token(let text):
                if firstTokenTime == nil { firstTokenTime = Date() }
                fullContent += text
            case .metrics(let prompt, let completion, let tps):
                finalMetrics = (prompt, completion, tps)
            case .tool(let call):
                AgentLogger.logInfo("🛠 [MLX-Provider] Tool indicated: \(call)")
            case .toolCall(let name, let arguments):
                AgentLogger.logInfo("🎯 [MLX-Provider] Native tool call: \(name)")
                collectedToolCalls.append(ToolCall(tool: name, ubid: nil, params: arguments))
            }
        }

        if fullContent.isEmpty && collectedToolCalls.isEmpty {
            throw ProviderError.emptyResponse
        }

        // Extract <think>...</think> block from raw content.
        // content → only the actual response (after </think>)
        // thinkBlock → the model's reasoning (for logging/planning use)
        let (extractedThink, cleanContent) = Self.extractThinkBlock(from: fullContent)

        let latency = Int(Date().timeIntervalSince(startTime) * 1000)
        let count = TokenCount(
            prompt: finalMetrics?.prompt ?? (messages.map { $0.content.count }.reduce(0, +) / 4),
            completion: finalMetrics?.completion ?? (fullContent.count / 4),
            total: (finalMetrics?.prompt ?? 0) + (finalMetrics?.completion ?? 0)
        )

        return CompletionResponse(
            taskID: request.taskID,
            providerUsed: providerID,
            content: cleanContent,
            thinkBlock: extractedThink.isEmpty ? nil : extractedThink,
            toolCalls: collectedToolCalls.isEmpty ? nil : collectedToolCalls,
            tokensUsed: count,
            latencyMs: latency,
            costUSD: 0
        )
    }

    /// Splits raw model output into (thinkContent, responseContent).
    /// Handles both <think>...</think> XML tags and the "Thinking Process:" plain text format.
    static func extractThinkBlock(from text: String) -> (think: String, response: String) {
        // Format A: <think>...</think> XML tags (standard Qwen 3.5 thinking mode)
        if let startRange = text.range(of: "<think>", options: .caseInsensitive),
           let endRange = text.range(of: "</think>", options: .caseInsensitive, range: startRange.upperBound..<text.endIndex) {
            let thinkContent = String(text[startRange.upperBound..<endRange.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
            let response = String(text[endRange.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines)
            return (thinkContent, response.isEmpty ? text : response)
        }

        // Format B: "Thinking Process:" plain text (when enable_thinking=true but model ignores XML)
        let thinkingPrefixes = ["thinking process:", "chain of thought:", "let me think:"]
        let lower = text.lowercased()
        if thinkingPrefixes.contains(where: { lower.hasPrefix($0) }) {
            // Find the last conclusion marker and return text after it
            let conclusionMarkers = ["final decision:", "final answer:", "final polish:", "output:"]
            for marker in conclusionMarkers {
                if let markerRange = text.range(of: marker, options: [.caseInsensitive, .backwards]) {
                    let afterMarker = String(text[markerRange.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines)
                    // Skip the marker line itself, take the next non-empty line
                    let lines = afterMarker.components(separatedBy: .newlines).filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
                    if let answer = lines.first {
                        let cleaned = answer.trimmingCharacters(in: .whitespacesAndNewlines)
                        if !cleaned.isEmpty { return (text, cleaned) }
                    }
                }
            }
            // No conclusion marker: return last short paragraph as the answer
            let paragraphs = text.components(separatedBy: "\n\n").map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
            if let last = paragraphs.last, last.count < 300, paragraphs.count > 1 {
                return (text, last)
            }
        }

        return ("", text)
    }
}
