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

        // Item 4: Measure wired memory budget in the background (does not block inference)
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
                AgentLogger.logInfo("⚠️ [v3-Wired] Measurement failed: \(error.localizedDescription)")
            }
        }

        // Item 6: Auto-load draft model if present at {modelDir}-draft (opt-in, no-op if absent)
        Task {
            await self.tryLoadDraftModel(for: url)
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
        parameters.kvBits = 4
        parameters.kvGroupSize = 64
        parameters.quantizedKVStart = 256
        parameters.topP = 0.9
        parameters.minP = 0.05
        // Item 5: Rotating KV Cache — caps unbounded KV growth; old entries evicted beyond window
        parameters.maxKVSize = 8192

        // additionalContext["enable_thinking"] is the official mlx-swift-lm API for Qwen 3.5.
        // false = skip <think> block entirely → dramatically faster responses for chat.
        let additionalContext: [String: any Sendable]? = enableThinking ? nil : ["enable_thinking": false]

        return AsyncStream(InferenceChunk.self) { continuation in
            let task = Task { [parameters] in
                do {
                    let userInput = UserInput(messages: mlxMessages, tools: tools, additionalContext: additionalContext)
                    let input = try await container.prepare(input: userInput)

                    // Item 4: Wired Memory ticket — pins weights+workspace in RAM during inference
                    let wiredTicket = self.makeWiredTicket()

                    // Item 6: Speculative Decoding — use draft model if loaded, else regular path
                    let resultStream: AsyncStream<Generation>
                    if let draftContainer = self.draftModelContainer {
                        // Extract draft LanguageModel (weights read-only after eval — thread-safe)
                        let draftBox = await draftContainer.perform { ctx in
                            UnsafeTransferBox<any LanguageModel>(ctx.model)
                        }
                        // Box LMInput to safely cross the @Sendable closure boundary
                        let inputBox = UnsafeTransferBox(input)
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
                            continuation.yield(.metrics(promptTokens: metrics.promptTokenCount, completionTokens: metrics.generationTokenCount, tps: metrics.tokensPerSecond))
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

    private func tryLoadDraftModel(for mainModelURL: URL) async {
        let draftURL = mainModelURL.deletingLastPathComponent()
            .appendingPathComponent(mainModelURL.lastPathComponent + "-draft")
        guard FileManager.default.fileExists(atPath: draftURL.path) else { return }
        do {
            let draft = try await loadModelContainer(from: draftURL)
            self.draftModelContainer = draft
            AgentLogger.logInfo("🚀 [v3-Speculative] Draft model ready: \(draftURL.lastPathComponent)")
        } catch {
            AgentLogger.logInfo("⚠️ [v3-Speculative] Draft model load failed: \(error.localizedDescription)")
        }
    }

    /// Explicitly loads a draft model for speculative decoding.
    /// The draft model must share the same tokenizer family as the main model.
    public func loadDraftModel(at url: URL) async throws {
        draftModelContainer = try await loadModelContainer(from: url)
        AgentLogger.logInfo("🚀 [v3-Speculative] Draft model explicitly loaded: \(url.lastPathComponent)")
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
}
