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

            // Cap Metal cache to 128 MB so the OS can reclaim memory under pressure
            MLX.Memory.cacheLimit = 128 * 1024 * 1024
        }
    }
    
    // MARK: - Core API (v3 Official)
    
    /// Loads a model container using the official v3 factory patterns.
    public func loadModel(at url: URL) async throws {
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
    }
    
    /// Generates tokens as an AsyncStream using official v3 stream patterns.
    public func generate(messages: [Message], systemPrompt: String? = nil, maxTokens: Int = 2048) async throws -> AsyncStream<InferenceChunk> {
        let startTime = Date()
        guard let container = modelContainer else {
            throw NSError(domain: "EliteAgent", code: 404, userInfo: [NSLocalizedDescriptionKey: "Engine not primed."])
        }
        
        let mlxMessages = messages.map { ["role": $0.role, "content": $0.content] }
        let parameters = GenerateParameters(maxTokens: maxTokens, temperature: 0.7)
        
        return AsyncStream(InferenceChunk.self) { continuation in
            let task = Task { [parameters] in
                do {
                    // Official v3: Prepare and generate inside the same context to avoid data races
                    let input = try await container.prepare(input: UserInput(messages: mlxMessages))
                    let resultStream = try await container.generate(input: input, parameters: parameters)
                    
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
                            AgentLogger.logInfo("🛠 Tool Call: \(String(describing: call))")
                            continuation.yield(.tool(String(describing: call)))
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
        
        if reload {
            await ModelSetupManager.shared.reloadCurrentModel()
        }
        
        AgentLogger.logAudit(level: .info, agent: "titan", message: "Hard Reset: Motor v3-Native olarak optimize edildi.")
    }
    
    public func unloadModel() async {
        self.cancelOngoingGenerations()
        self.modelContainer = nil
        self.loadedModelID = nil
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
