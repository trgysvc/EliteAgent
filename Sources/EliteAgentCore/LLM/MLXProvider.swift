import Foundation
import MLX
import MLXLLM

/// Orchestration-layer provider that bridges the generic Completion API to the 
/// hardware-accelerated InferenceActor (Titan Engine).
public actor MLXProvider: LocalLLMProvider {
    public static let shared = MLXProvider(providerID: .mlx)
    
    public nonisolated let providerID: ProviderID
    public nonisolated let providerType: ProviderType = .local
    public let capabilities: Set<Capability> = [.think, .code, .general]
    public let costPer1KTokens: Decimal = 0
    public let maxContextTokens: Int = 16384 // Synchronized with InferenceActor
    public private(set) var status: ProviderStatus = .ready
    
    public nonisolated var isLoaded: Bool {
        // Since status is a simple enum and isLoaded is computed, 
        // we use this for fast, thread-safe state checks in the Orchestrator.
        return true // Simplified for nonisolated access, or use a separate atomic flag if needed.
    }
    
    public init(providerID: ProviderID) {
        self.providerID = providerID
        self.status = .ready
    }
    
    public func healthCheck() async -> Bool {
        return true // InferenceActor manages its own health
    }
    
    public func loadModel(_ modelName: String) async throws {
        self.status = .loading
        do {
            let modelURL = getModelURL(for: modelName)
            
            // Phase 1: Meta-loading (Initializing Structures)
            self.status = .loading
            
            // Phase 2: Priming (VRAM Allocation & Weight Transfer)
            // The InferenceActor will trigger the actual VRAM state, but we 
            // signal our intent here for the UI layer.
            self.status = .priming
            
            // v21.5 / v24.3: VLM Detection — match explicit VLM families only.
            // qwen3 and qwen3.5 are text-only; actual VLMs require a -vl- suffix or known VLM family name.
            // InferenceActor.loadModel also auto-detects from config.json as a secondary guard.
            let lowerName = modelName.lowercased()
            let normalizedID = lowerName.replacingOccurrences(of: "-", with: "")
            let vlmIndicators = ["qwen2vl", "qwen25vl", "qwen3vl", "pixtral", "lfm2vl", "llava", "fastvlm", "smolvlm", "paligemma", "idefics"]
            let asVLM = vlmIndicators.contains { normalizedID.contains($0) }
                     || lowerName.contains("-vl-") || lowerName.hasSuffix("-vl") || lowerName.contains("-vision-")
            
            AgentLogger.logAudit(level: .info, agent: "titan", message: "Model Loading Path Selected: \(asVLM ? "VLM (Multimodal Bridge)" : "LLM (Standard Text)") for \(modelName)")
            
            try await InferenceActor.shared.loadModel(at: modelURL, asVLM: asVLM)
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
    
    private func getModelURL(for name: String) -> URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return appSupport.appendingPathComponent("EliteAgent/Models/\(name)")
    }
    
    public func complete(_ request: CompletionRequest, useSafeMode: Bool) async throws -> CompletionResponse {
        let startTime = Date()
        
        // v10.5.5: Full Transparency - Log Input
        AgentLogger.logAudit(level: .info, agent: "titan", message: "Titan Request | System: \(request.systemPrompt) | Last Msg: \(request.messages.last?.content ?? "")")
        
        // v9.2: Pass full message context from Orchestrator to InferenceActor
        let messages = request.messages.map { Message(role: $0.role, content: $0.content) }
        
        let stream = await InferenceActor.shared.generate(
            messages: messages, 
            systemPrompt: request.systemPrompt,
            maxTokens: request.maxTokens,
            useSafeMode: useSafeMode,
            untrustedContext: request.untrustedContext
        )
        
        var fullContent = ""
        var firstTokenTime: Date?
        var tokenCount = 0
        
        for await chunk in stream {
            if firstTokenTime == nil {
                firstTokenTime = Date()
                let initialLatency = String(format: "%.1fs", firstTokenTime!.timeIntervalSince(startTime))
                AgentLogger.logAudit(level: .info, agent: "titan", message: "Titan: First token arrived (\(initialLatency))")
            }
            fullContent += chunk
            tokenCount += 1
        }
        
        // v9.9.13: SILENCE FAILURE DETECTION
        if fullContent.isEmpty {
            AgentLogger.logAudit(level: .error, agent: "titan", message: "Titan: Silence failure detected - no tokens generated.")
            throw ProviderError.emptyResponse
        }
        
        let totalTime = Date().timeIntervalSince(firstTokenTime ?? startTime)
        let tps = totalTime > 0 ? Double(tokenCount) / totalTime : 0
        AgentLogger.logAudit(level: .info, agent: "titan", message: "Titan: Generation speed: \(Int(tps)) t/s")
        
        let latency = Int(Date().timeIntervalSince(startTime) * 1000)
        
        // Estimates for local token counts
        let count = TokenCount(
            prompt: request.messages.map { $0.content.count }.reduce(0, +) / 4,
            completion: fullContent.count / 4,
            total: (request.messages.map { $0.content.count }.reduce(0, +) + fullContent.count) / 4
        )
        
        // v10.5.5: Full Transparency - Log Output
        AgentLogger.logAudit(level: .info, agent: "titan", message: "Titan Response | Raw: \(fullContent)")
        AgentLogger.logAudit(level: .info, agent: "titan", message: "Inference Complete | Model: Local Titan | Tokens: \(count.total) (\(count.prompt)p/\(count.completion)c) | Latency: \(latency)ms")
        
        return CompletionResponse(
            taskID: request.taskID,
            providerUsed: providerID,
            content: fullContent,
            tokensUsed: count,
            latencyMs: latency,
            costUSD: 0
        )
    }
}
