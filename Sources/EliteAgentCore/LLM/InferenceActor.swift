import Foundation
@preconcurrency import MLX
@preconcurrency import MLXLLM
@preconcurrency import MLXLMCommon
import MLXLMTokenizers
import MLXLMHFAPI
import MLXHuggingFace
import Metal
import os
import CryptoKit

/// v31.3: Official MLX-LM v3 Titan Engine (Master Kernel)
/// Strictly adheres to MLX v0.31.3 and MLX-LM v3.31.3 official standards.
public actor InferenceActor {
    public static let shared = InferenceActor()
    
    // MARK: - State Management
    
    private var modelContainer: ModelContainer?
    private var currentGenerationTask: Task<Void, Never>?
    private var isModelLoading = false
    
    public private(set) var loadedModelID: String?
    public var isModelLoaded: Bool { modelContainer != nil }
    public var isDraftModelLoaded: Bool { draftModelContainer != nil }
    public var isBusy: Bool { currentGenerationTask != nil }
    
    // Performance Metrics
    public var lastTPS: Double = 0
    public var lastLatency: Int = 0
    public var nextRequestReducedContext: Bool = false

    private let inferenceLog = OSLog(subsystem: "app.eliteagent.titan", category: "InferencePerformance")
    private let maxActivations = 4096
    nonisolated public let sharedBuffer: MetalBufferWrapper

    // Item 4: Wired Memory — measured after model load, applied per inference request
    private var wiredMeasurement: WiredMemoryMeasurement? = nil
    private let wiredPolicyID = UUID()

    // Item 6: Speculative Decoding — draft model container loaded alongside main model
    private var draftModelContainer: ModelContainer? = nil

    // @unchecked Sendable wrapper to transfer non-Sendable MLX types (LMInput, LanguageModel)
    // across async boundaries inside @Sendable closures. Mirrors MLXLMCommon's internal SendableBox.
    private final class UnsafeTransferBox<T>: @unchecked Sendable {
        var value: T?
        init(_ value: T) { self.value = value }
        func take() -> T {
            defer { value = nil }
            return value!
        }
    }
    
    // Process Visualization
    private var stepContinuation: AsyncStream<ProcessStep>.Continuation?
    public var processStream: AsyncStream<ProcessStep> {
        AsyncStream { continuation in
            stepContinuation = continuation
        }
    }

    // MARK: - Initialization
    
    // Stored so loadModel/generate can wrap MLX calls in withDefaultDevice(.cpu) when needed.
    nonisolated public let isCPUOnly: Bool

    private init() {
        let cpuOnly = ProcessInfo.processInfo.arguments.contains("--cpu-only")
        self.isCPUOnly = cpuOnly

        if cpuOnly {
            // CPU-only: skip Metal buffer, skip cache limit (no GPU cache)
            self.sharedBuffer = MetalBufferWrapper(nil)
            AgentLogger.logInfo("[MLX-Opt] Forced CPU-only mode for CLI stability.")
        } else {
            let device = MTLCreateSystemDefaultDevice()
            let size = maxActivations * MemoryLayout<Float>.size
            let buffer = device?.makeBuffer(length: size, options: .storageModeShared)
            self.sharedBuffer = MetalBufferWrapper(buffer)

            // Cap Metal cache to 2 GB for M-series performance stability
            MLX.Memory.cacheLimit = 2 * 1024 * 1024 * 1024
        }
    }
    
    // MARK: - Core API (v3 Official)
    
    /// Loads a model container using the official v3 factory patterns.
    public func loadModel(at url: URL) async throws {
        guard !isModelLoading else {
            AgentLogger.logInfo("⚠️ [v3-Engine] Load requested but already in progress. Skipping.")
            return
        }
        
        isModelLoading = true
        defer { isModelLoading = false }
        
        self.cancelOngoingGenerations()
        AgentLogger.logInfo("📦 [v3-Engine] Loading Model Container from: \(url.lastPathComponent)")
        
        // Official v3: Use the global loadModelContainer for automated orchestration
        let container = try await loadModelContainer(
            from: url
        )
        
        self.modelContainer = container
        self.loadedModelID = url.lastPathComponent

        await MainActor.run {
            ModelSetupManager.shared.isModelReady = true
            ModelSetupManager.shared.loadState = .idle
        }

        if let modelID = loadedModelID {
            AgentLogger.logInfo("✅ [v3-Engine] Titan Core Primed: \(modelID)")
        }

        // Item 4 → Item 6: Wired memory measurement runs first; draft model loads after.
        // Sequential ordering prevents simultaneous RAM pressure that triggers the watchdog.
        let modelID = url.lastPathComponent
        Task { [container] in
            do {
                let measureParams = GenerateParameters(maxTokens: 32, temperature: 0.6)
                let m = try await container.perform { ctx in
                    try await WiredMemoryUtils.tune(context: ctx, tokenCount: 64, parameters: measureParams)
                }
                self.wiredMeasurement = m
                let wb = m.weightBytes / 1024 / 1024
                let kb = m.kvBytes / 1024 / 1024
                AgentLogger.logInfo("📊 [v3-Wired] Budget measured — weights:\(wb)MB kv:\(kb)MB workspace:\(m.workspaceBytes/1024/1024)MB")
            } catch {
                AgentLogger.logInfo("⚠️ [v3-Wired] Measurement failed (draft load will still proceed): \(error.localizedDescription)")
            }
            // Wired measurement done (success or fail). Safe to load draft now.
            await ModelManager.shared.onWiredMemoryReady(for: modelID)
        }
    }
    
    /// Generates tokens as an AsyncStream using official v3 stream patterns.
    /// - Parameters:
    ///   - tools: Optional ToolSpec array ([String: any Sendable]). Qwen 3.5 uses xmlFunction format
    ///            which is auto-detected from model_type="qwen3_5" in config.json.
    ///   - enableThinking: Pass false to suppress Qwen 3.5 <think> blocks via additionalContext.
    ///            Use false for chat/classification, true (default) for planning/reasoning tasks.
    public func generate(
        messages: [Message],
        systemPrompt: String? = nil,
        maxTokens: Int = 2048,
        tools: [[String: any Sendable]]? = nil,
        enableThinking: Bool = true
    ) async throws -> AsyncStream<InferenceChunk> {
        let startTime = Date()
        guard let container = modelContainer else {
            throw NSError(domain: "EliteAgent", code: 404, userInfo: [NSLocalizedDescriptionKey: "Engine not primed."])
        }

        // Build message array: prepend system message if provided (was silently ignored before).
        var mlxMessages: [[String: any Sendable]] = []
        if let sys = systemPrompt, !sys.isEmpty {
            mlxMessages.append(["role": "system", "content": sys])
        }
        mlxMessages.append(contentsOf: messages.map { ["role": $0.role, "content": $0.content] })

        var parameters = GenerateParameters(maxTokens: maxTokens, temperature: 0.6)
        parameters.repetitionPenalty = 1.15
        parameters.repetitionContextSize = 64
        
        // Item 6: Speculative Decoding Stability — MLX requires a KVCacheSimple (FP16, trimmable).
        // QuantizedKVCache is NOT trimmable, so ANY quantization parameter (kvBits, quantizedKVStart,
        // kvGroupSize) must be left at their defaults (nil/unset) when the draft model is active.
        // Setting quantizedKVStart=0 or kvGroupSize while kvBits=nil can still trigger a
        // QuantizedKVCache in some mlx-swift-lm versions, causing KVCacheError at runtime.
        if draftModelContainer != nil {
            AgentLogger.logInfo("📊 [v3-Speculative] KV cache: FP16/Simple (trimmable). quantizedKVStart and kvGroupSize left at defaults.")
            parameters.kvBits = nil
            parameters.maxKVSize = nil
            // quantizedKVStart and kvGroupSize intentionally NOT set — defaults prevent QuantizedKVCache.
        } else {
            parameters.kvBits = 4
            parameters.kvGroupSize = 64
            parameters.quantizedKVStart = 256
            parameters.maxKVSize = 8192 // Standard rotating cache for non-speculative path
        }
        parameters.topP = 0.9
        parameters.minP = 0.05

        // additionalContext: always nil. Passing enable_thinking=false (or 0) through swift-jinja
        // breaks because Value.compare() has no boolean case (sameas) and isEquivalent() type
        // mismatch (Int vs Bool) causes the template's != false check to return true, forcing
        // <think> into the generation prompt and consuming the token budget before the real answer.
        // The model self-selects thinking vs no-thinking based on task complexity.
        // Think blocks are cleaned by extractThinkBlock in MLXProvider.complete().
        let additionalContext: [String: any Sendable]? = nil

        return AsyncStream(InferenceChunk.self) { continuation in
            let task = Task { [parameters] in
                do {
                    let userInput = UserInput(messages: mlxMessages, tools: tools, additionalContext: additionalContext)
                    let input = try await container.prepare(input: userInput)
                    
                    // Item 4: Wired Memory ticket — pins weights+workspace in RAM during inference
                    let wiredTicket = self.makeWiredTicket()

                    // Item 6: Speculative Decoding — use draft model if loaded, else regular path.
                    // Two boxes: inputBox for the speculative attempt, inputFallback for the standard
                    // generation fallback in case the model's makeCache() returns a non-trimmable cache.
                    let resultStream: AsyncStream<Generation>
                    if let draftContainer = self.draftModelContainer {
                        let draftBox = await draftContainer.perform { ctx in
                            UnsafeTransferBox<any LanguageModel>(ctx.model)
                        }
                        let inputBox = UnsafeTransferBox(input)
                        let inputFallback = UnsafeTransferBox(input)

                        do {
                            resultStream = try await container.perform { mainCtx -> AsyncStream<Generation> in
                                try MLXLMCommon.generate(
                                    input: inputBox.take(),
                                    parameters: parameters,
                                    context: mainCtx,
                                    draftModel: draftBox.take(),
                                    numDraftTokens: 4,
                                    wiredMemoryTicket: wiredTicket
                                )
                            }
                            AgentLogger.logInfo("🚀 [v3-Speculative] Speculative decoding active (numDraftTokens=4)")
                        } catch {
                            // Model's KV cache is not trimmable — disable draft model permanently and
                            // fall back to standard generation so the current request still completes.
                            AgentLogger.logInfo("⚠️ [v3-Speculative] Cache incompatible (\(error.localizedDescription)). Draft model disabled. Falling back to standard generation.")
                            self.draftModelContainer = nil
                            resultStream = try await container.generate(input: inputFallback.take(), parameters: parameters, wiredMemoryTicket: wiredTicket)
                        }
                    } else {
                        resultStream = try await container.generate(input: input, parameters: parameters, wiredMemoryTicket: wiredTicket)
                    }

                    for await chunk in resultStream {
                        if Task.isCancelled { break }

                        switch chunk {
                        case .chunk(let text):
                            continuation.yield(.token(text))
                            updateSharedBuffer(with: text.count)
                        case .info(let metrics):
                            self.lastTPS = metrics.tokensPerSecond
                            AgentLogger.logInfo("📊 [v3-Engine] TPS: \(metrics.tokensPerSecond.formatted())")
                            
                            var specMetrics: SpeculativeDecodingMetrics? = nil
                            
                            // v3.31.3: Use Mirror to safely extract speculative metrics across library versions
                            let mirror = Mirror(reflecting: metrics)
                            var draftCount = 0
                            var acceptedCount = 0
                            for child in mirror.children {
                                if child.label == "draftTokenCount" || child.label == "draftCount" {
                                    draftCount = (child.value as? Int) ?? 0
                                }
                                if child.label == "acceptedDraftTokenCount" || child.label == "acceptedCount" {
                                    acceptedCount = (child.value as? Int) ?? 0
                                }
                            }

                            if draftCount > 0 {
                                specMetrics = SpeculativeDecodingMetrics(
                                    totalDraftTokensGenerated: draftCount,
                                    acceptedDraftTokens: acceptedCount
                                )
                                self.logSpeculativeMetrics(metrics: specMetrics!)
                            }
                            
                            continuation.yield(.metrics(
                                promptTokens: metrics.promptTokenCount,
                                completionTokens: metrics.generationTokenCount,
                                tps: metrics.tokensPerSecond,
                                speculative: specMetrics
                            ))
                        case .toolCall(let call):
                            // Convert mlx-swift-lm ToolCall → InferenceChunk.toolCall
                            AgentLogger.logInfo("🎯 [v3-Engine] Native tool call: \(call.function.name)")
                            let args = call.function.arguments.mapValues { AnyCodable($0.anyValue) }
                            continuation.yield(.toolCall(name: call.function.name, arguments: args))
                        @unknown default:
                            break
                        }
                    }
                    self.lastLatency = Int(Date().timeIntervalSince(startTime) * 1000)
                    continuation.finish()
                } catch {
                    AgentLogger.logError("❌ [v3-Engine] Generation Error: \(error)")
                    continuation.finish()
                }
                self.currentGenerationTask = nil
            }
            self.currentGenerationTask = task
        }
    }
    
    // MARK: - Universal Interface (Orchestrator Support)
    
    public func infer(prompt: String, config: InferenceConfig) async throws -> AsyncStream<InferenceChunk> {
        let activeProvider = await ModelStateManager.shared.activeProvider
        let messages = [Message(role: "user", content: prompt)]
        
        switch activeProvider {
        case .localTitanEngine(let modelID):
            if self.loadedModelID != modelID {
                try await ModelManager.shared.load(modelID)
            }
            return try await self.generate(messages: messages, maxTokens: config.maxTokens)
            
        case .cloudOpenRouter:
            // v3-Native: Cloud delegation via existing CloudProvider logic
            let vault = try VaultManager(configURL: PathConfiguration.shared.vaultURL)
            let cloud = try CloudProvider(providerID: .openrouter, vaultManager: vault)
            let request = CompletionRequest(
                taskID: UUID().uuidString,
                systemPrompt: config.systemPrompt ?? "",
                messages: messages,
                maxTokens: config.maxTokens,
                sensitivityLevel: .public,
                complexity: 3
            )
            let response = try await cloud.complete(request, useSafeMode: false)
            return AsyncStream { continuation in
                continuation.yield(.token(response.content))
                continuation.finish()
            }
            
        case .none:
            throw NSError(domain: "EliteAgent", code: 503, userInfo: [NSLocalizedDescriptionKey: "No provider selected."])
        }
    }
    
    // MARK: - Wired Memory & Draft Model Helpers

    private func makeWiredTicket() -> WiredMemoryTicket? {
        guard !isCPUOnly, let m = wiredMeasurement else { return nil }
        let policy = WiredBudgetPolicy(baseBytes: m.weightBytes + m.workspaceBytes, id: wiredPolicyID)
        return policy.ticket(size: m.kvBytes, kind: .active)
    }

    /// Called by ModelManager after the draft model is confirmed on disk.
    /// Validates tokenizer vocabulary size compatibility before enabling speculative decoding.
    /// Draft and main model MUST share the same vocabulary — different families are incompatible.
    public func loadDraftModel(at url: URL) async throws {
        guard modelContainer != nil else {
            throw NSError(domain: "EliteAgent", code: 412,
                          userInfo: [NSLocalizedDescriptionKey: "Main model not loaded — cannot load draft."])
        }

        // Vocabulary size check: draft and main must share the same tokenizer.
        // Read vocab sizes from tokenizer.json via UNOExternalBridge (no JSONDecoder — UNO rule).
        let mainDir = loadedModelID.map { PathConfiguration.shared.modelsURL.appendingPathComponent($0) }
        let mainVocabSize = readVocabSize(at: mainDir)
        let draftVocabSize = readVocabSize(at: url)

        if let main = mainVocabSize, let draft = draftVocabSize, main != draft {
            AgentLogger.logInfo("⛔ [v3-Speculative] Vocab mismatch — main:\(main) draft:\(draft). Speculative decoding disabled.")
            throw NSError(domain: "EliteAgent", code: 409,
                          userInfo: [NSLocalizedDescriptionKey: "Draft model tokenizer incompatible (vocab \(draft) ≠ \(main))."])
        }

        // Architecture compatibility check: speculative decoding requires ALL KV caches to be
        // trimmable. Hybrid SSM-Attention models (e.g. Qwen3.5) have MambaCache layers which are
        // never trimmable. Loading the draft model for such architectures wastes RAM with no benefit.
        guard let mainContainer = modelContainer else { return }
        // Return Bool (Sendable) — returning [any KVCache] across the @Sendable closure boundary
        // violates Swift 6 data-race safety since KVCache is not Sendable.
        let allTrimmable = try await mainContainer.perform { ctx in
            ctx.model.newCache(parameters: nil).allSatisfy { $0.isTrimmable }
        }
        guard allTrimmable else {
            AgentLogger.logInfo("⛔ [v3-Speculative] Main model has non-trimmable KV cache (hybrid SSM/Mamba architecture). Draft model not loaded — speculative decoding is architecturally incompatible.")
            throw NSError(domain: "EliteAgent", code: 415,
                          userInfo: [NSLocalizedDescriptionKey: "Speculative decoding requires trimmable KV caches. This model architecture (hybrid SSM) is incompatible. Draft model not loaded."])
        }

        draftModelContainer = try await loadModelContainer(from: url)
        AgentLogger.logInfo("🚀 [v3-Speculative] Draft model loaded: \(url.lastPathComponent) (vocab:\(draftVocabSize ?? 0))")
    }

    /// Reads vocab size from a model directory's tokenizer.json via UNOExternalBridge.
    private func readVocabSize(at url: URL?) -> Int? {
        guard let url else { return nil }
        let tokenizerURL = url.appendingPathComponent("tokenizer.json")
        guard let data = try? Data(contentsOf: tokenizerURL),
              let dict = UNOExternalBridge.resolveDictionary(from: data),
              let model = dict["model"] as? [String: Any],
              let vocab = model["vocab"] as? [String: Any] else { return nil }
        return vocab.count
    }

    // MARK: - Maintenance & Self-Healing

    public func cancelOngoingGenerations() {
        currentGenerationTask?.cancel()
        currentGenerationTask = nil
        AgentLogger.logInfo("⚠️ [v3-Engine] All generation tasks halted.")
    }
    
    public func clearCache() {
        MLX.Memory.clearCache()
        AgentLogger.logInfo("🧹 [v3-Engine] VRAM Cache Purged.")
    }
    
    public func clearContext() {
        AgentLogger.logInfo("🧹 [v3-Engine] Context invalidated.")
        self.cancelOngoingGenerations()
    }
    
    public func restart(reload: Bool = false) async {
        AgentLogger.logAudit(level: .warn, agent: "titan", message: "Hard Reset: Titan Motoru Yeniden Başlatılıyor...")
        
        self.cancelOngoingGenerations()
        self.clearCache()

        self.modelContainer = nil
        self.loadedModelID = nil
        self.draftModelContainer = nil
        self.wiredMeasurement = nil

        if reload {
            await ModelSetupManager.shared.reloadCurrentModel()
        }
        
        AgentLogger.logAudit(level: .info, agent: "titan", message: "Hard Reset: Motor v3-Native olarak optimize edildi.")
    }
    
    public func unloadModel() async {
        self.cancelOngoingGenerations()
        self.modelContainer = nil
        self.loadedModelID = nil
        self.draftModelContainer = nil
        self.wiredMeasurement = nil
        self.clearCache()
        
        await MainActor.run {
            ModelSetupManager.shared.isModelReady = false
            ModelSetupManager.shared.loadState = .idle
        }
    }
    
    public func setNextRequestConfig(reducedContext: Bool) {
        self.nextRequestReducedContext = reducedContext
    }
    
    public func getAverageTPS() -> Double { return lastTPS }
    public func getLastLatency() -> Int { return lastLatency }
    
    private func updateSharedBuffer(with activationValue: Int) {
        guard let buffer = sharedBuffer.buffer else { return }
        let ptr = buffer.contents().bindMemory(to: Float.self, capacity: 1)
        ptr[0] = Float(activationValue)
    }

    /// Logs speculative decoding efficiency based on acceptance rate.
    private func logSpeculativeMetrics(metrics: SpeculativeDecodingMetrics) {
        let rate = metrics.acceptanceRate * 100.0
        let formattedRate = String(format: "%.1f", rate)
        
        if rate >= 60.0 {
            AgentLogger.logInfo("🚀 [SpecDec Mükemmel] Kabul Oranı: %\(formattedRate) (Draft: \(metrics.totalDraftTokensGenerated), Kabul: \(metrics.acceptedDraftTokens))")
        } else if rate >= 35.0 {
            AgentLogger.logInfo("📊 [SpecDec Normal] Kabul Oranı: %\(formattedRate)")
        } else {
            AgentLogger.logInfo("⚠️ [SpecDec Verimsiz] Kabul Oranı: %\(formattedRate). Taslak model overhead yaratıyor olabilir.")
        }
    }
}
