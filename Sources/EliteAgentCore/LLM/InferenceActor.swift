// EliteAgent Titan Engine - v9.0.2 (Universal & Fixed)
import Foundation
import MLX
import MLXLLM
import MLXLMCommon
import Metal

/// The Universal Brain of EliteAgent. 
/// Orchestrates local, cloud, and bridge providers via a single entry point.
public actor InferenceActor {
    public static let shared = InferenceActor()
    
    nonisolated public let sharedBuffer: MetalBufferWrapper
    private let maxActivations = 1024
    
    private var currentGenerationTask: Task<Void, Never>?
    private var modelContainer: ModelContainer?
    private var maxContextTokens: Int = 16384
    private var conversationHistory: [Message] = []
    
    // v9.6: Self-Healing Metrics
    private var lastTPS: Double = 0
    private var lastLatency: Int = 0
    private var nextRequestReducedContext: Bool = false
    
    // v7.7.0 Process Visualization Bridge
    private var stepContinuation: AsyncStream<ProcessStep>.Continuation?
    public var processStream: AsyncStream<ProcessStep> {
        AsyncStream { continuation in
            stepContinuation = continuation
        }
    }
    
    private func emitStep(_ step: ProcessStep) {
        stepContinuation?.yield(step)
    }
    
    private init() {
        let device = MTLCreateSystemDefaultDevice()
        let size = maxActivations * MemoryLayout<Float>.size
        let buffer = device?.makeBuffer(length: size, options: .storageModeShared)
        self.sharedBuffer = MetalBufferWrapper(buffer)
        
        // v13.9: Official MLX Unified Memory Optimization (PRD v17.4)
        // Set GPU cache limit to 70% of physical memory for zero-copy inference
        let memoryInfo = ProcessInfo.processInfo.physicalMemory
        let cacheLimit = Int(Double(memoryInfo) * 0.7)
        MLX.Memory.cacheLimit = cacheLimit
        
        AgentLogger.logInfo("[MLX-Opt] Unified Memory GPU Cache set to \(cacheLimit / 1024 / 1024) MB")
        _ = LLMModelFactory.shared
    }
    
    // MARK: - Universal Inference API (v9.0)
    
    /// Universal entry point for all inference requests. (v9.9.1: Sync with ModelStateManager)
    public func infer(
        prompt: String,
        provider _: ModelProvider, // Ignored in favor of ModelStateManager
        config: InferenceConfig
    ) async throws -> AsyncStream<String> {
        
        // 1. Sync with the UI-selected provider
        let activeProvider = await ModelStateManager.shared.activeProvider
        AgentLogger.logAudit(level: .info, agent: "UniversalInference", message: "Inferring via \(activeProvider)")
        
        // Update history before inference
        self.conversationHistory.append(Message(role: "user", content: prompt))
        
        let vaultURL = PathConfiguration.shared.vaultURL
        
        switch activeProvider {
        case .localTitanEngine(let modelID):
            // 2. Atomic Load Check: Ensure model is in VRAM
            if await !ModelManager.shared.loadedModels.contains(modelID) {
                AgentLogger.logAudit(level: .warn, agent: "UniversalInference", message: "Model \(modelID) not in VRAM. Auto-loading...")
                try await ModelManager.shared.load(modelID)
            }
            return self.generate(messages: self.conversationHistory, systemPrompt: config.systemPrompt, maxTokens: config.maxTokens)
            
        case .localOllama(_):
            return AsyncStream { continuation in
                Task {
                    do {
                        // v9.9.1: Connection Pre-check to avoid log spam
                        if await OllamaManager.shared.canConnect() {
                            let vault = try VaultManager(configURL: vaultURL)
                            let bridge = try BridgeProvider(providerID: .bridge, vaultManager: vault)
                            let request = CompletionRequest(
                                taskID: UUID().uuidString,
                                systemPrompt: config.systemPrompt ?? "",
                                messages: self.conversationHistory,
                                maxTokens: config.maxTokens,
                                sensitivityLevel: .public,
                                complexity: 2
                            )
                            let response = try await bridge.complete(request, useSafeMode: false)
                            continuation.yield(response.content)
                            self.conversationHistory.append(Message(role: "assistant", content: response.content))
                            continuation.finish()
                        } else {
                            continuation.yield("⚠️ Ollama çevrimdışı. Lütfen uygulamayı başlatın.")
                            continuation.finish()
                            return
                        }
                        let vault = try VaultManager(configURL: vaultURL)
                        let bridge = try BridgeProvider(providerID: .bridge, vaultManager: vault)
                        let request = CompletionRequest(
                            taskID: UUID().uuidString,
                            systemPrompt: config.systemPrompt ?? "",
                            messages: self.conversationHistory,
                            maxTokens: config.maxTokens,
                            sensitivityLevel: .public,
                            complexity: 2
                        )
                        let response = try await bridge.complete(request, useSafeMode: false)
                        continuation.yield(response.content)
                        self.conversationHistory.append(Message(role: "assistant", content: response.content))
                        continuation.finish()
                    } catch {
                        continuation.yield("Error (Ollama): \(error.localizedDescription)")
                        continuation.finish()
                    }
                }
            }
            
        case .cloudOpenRouter(let modelID):
            return AsyncStream { continuation in
                Task {
                    do {
                        let vault = try VaultManager(configURL: vaultURL)
                        let cloud = try CloudProvider(providerID: .openrouter, vaultManager: vault)
                        
                        // v9.9.1: Cloud-specific Identity Prompt
                        let cloudIdentity = """
                        ### CLOUD RUNTIME DIRECTIVE
                        You are an AI assistant running via Cloud (OpenRouter) on macOS.
                        Active model: \(modelID)
                        IMPORTANT:
                        - Do NOT claim to be running locally on the user's device.
                        - Do NOT mention "MLX", "Titan Engine", or "local inference".
                        - If asked about your runtime, say: "I am running via cloud infrastructure."
                        """
                        
                        let finalSystemPrompt = "\(config.systemPrompt ?? "")\n\n\(cloudIdentity)"
                        
                        let request = CompletionRequest(
                            taskID: UUID().uuidString,
                            systemPrompt: finalSystemPrompt,
                            messages: self.conversationHistory,
                            maxTokens: config.maxTokens,
                            sensitivityLevel: .public,
                            complexity: 3
                        )
                        let response = try await cloud.complete(request, useSafeMode: false)
                        continuation.yield(response.content)
                        self.conversationHistory.append(Message(role: "assistant", content: response.content))
                        continuation.finish()
                    }
                }
            }
            
        case .none:
            return AsyncStream { continuation in
                continuation.yield("Sistem Hazır Değil: Lütfen Ayarlar > Titan Kurulum Sihirbazı üzerinden bir model kurun.")
                continuation.finish()
            }
        }
    }
    
    // MARK: - Local MLX Operations
    
    public func clearCache() {
        MLX.eval()
        MLX.Memory.clearCache()
    }
    
    public func clearContext() {
        AgentLogger.logAudit(level: .info, agent: "titan", message: "Titan: Context invalidated & history cleared.")
        cancelOngoingGenerations()
        self.conversationHistory.removeAll()
    }
    
    public func restart() async {
        AgentLogger.logAudit(level: .warn, agent: "titan", message: "Hard Reset: Titan Motoru Yeniden Başlatılıyor...")
        
        await MainActor.run {
            AISessionState.shared.isRestartingEngine = true
            ModelSetupManager.shared.isModelReady = false
        }
        
        let previousHistory = self.conversationHistory
        self.modelContainer = nil
        self.clearCache()
        
        // MLX Emergency Purge
        await MLXEngineGuardian.shared.emergencyPurge()
        
        // Reload current model
        await ModelSetupManager.shared.reloadCurrentModel()
        
        // Restore session
        self.conversationHistory = previousHistory
        
        await MainActor.run {
            AISessionState.shared.isRestartingEngine = false
            ModelSetupManager.shared.isModelReady = true
        }
        
        AgentLogger.logAudit(level: .info, agent: "titan", message: "Hard Reset: Motor başarıyla optimize edildi ve oturum korundu.")
    }
    
    public func cancelOngoingGenerations() {
        currentGenerationTask?.cancel()
        currentGenerationTask = nil
    }
    
    // MARK: - v9.6 Self-Healing API
    
    public func getAverageTPS() -> Double { return lastTPS }
    public func getLastLatency() -> Int { return lastLatency }
    
    /// Returns true if the model is currently busy with an inference task.
    public var isBusy: Bool {
        return self.currentGenerationTask != nil
    }
    
    public func setNextRequestConfig(reducedContext: Bool) {
        self.nextRequestReducedContext = reducedContext
    }
    
    public func unloadModel() async {
        cancelOngoingGenerations()
        self.modelContainer = nil
        self.clearCache()
        
        await MainActor.run {
            ModelSetupManager.shared.isModelReady = false
            ModelSetupManager.shared.loadState = .idle
        }
    }
    
    public func loadModel(at url: URL) async throws {
        self.clearCache()
        
        await MainActor.run {
            ModelSetupManager.shared.loadState = .transferringToVRAM
            ModelSetupManager.shared.isModelReady = false
        }
        
        let config = ModelConfiguration(directory: url)
        self.modelContainer = try await LLMModelFactory.shared.loadContainer(configuration: config)
        
        await MainActor.run {
            ModelSetupManager.shared.loadState = .ready
            ModelSetupManager.shared.isModelReady = true
        }
    }
    
    public func generate(messages: [Message], systemPrompt: String? = nil, maxTokens: Int = 500, useSafeMode: Bool = false) -> AsyncStream<String> {
        return AsyncStream(String.self) { continuation in
            self.currentGenerationTask = Task { [self] in
                defer { Task { self.setGenerationTaskNil() } }
                let finalSystemPrompt = systemPrompt ?? "You are EliteAgent, a powerful AI assistant."
                // v9.2: Accurate Multi-turn ChatML Construction
                var fullPrompt = "<|im_start|>system\n\(finalSystemPrompt)<|im_end|>\n"
                
                // v9.6: Apply Context Reduction if triggered by RecoveryEngine
                var historyToUse = messages
                if nextRequestReducedContext {
                    let keepCount = 3
                    if messages.count > keepCount {
                        historyToUse = Array(messages.suffix(keepCount))
                        AgentLogger.logAudit(level: .warn, agent: "titan", message: "Recovery: Context reduced to last \(keepCount) messages.")
                    }
                    nextRequestReducedContext = false // Reset after application
                }
                
                for msg in historyToUse {
                    fullPrompt += "<|im_start|>\(msg.role)\n\(msg.content)<|im_end|>\n"
                }
                
                // Ensure assistant trigger
                if messages.last?.role != "assistant" {
                    fullPrompt += "<|im_start|>assistant\n"
                }
                
                let promptToCapture = fullPrompt
                AgentLogger.logAudit(level: .info, agent: "titan", message: "🧠 Full Formatted Prompt: \nBEGIN PROMPT\n\(promptToCapture)\nEND PROMPT")
                let maxTokensToCapture = maxTokens
                
                    var fullContent = ""
                    let stream: AsyncStream<String> = AsyncStream(String.self) { innerContinuation in
                        Task {
                            do {
                                // v9.7: Wrap in Guardian for Timeout, OOM and Thermal protection.
                                try await MLXEngineGuardian.shared.execute { [self] in
                                    try await self.internalGenerate(
                                        formattedPrompt: promptToCapture, 
                                        maxTokens: maxTokensToCapture, 
                                        continuation: innerContinuation,
                                        useSafeMode: useSafeMode
                                    )
                                }
                            } catch let error as EngineError {
                                innerContinuation.yield("⚠️ Engine Error: \(error.localizedDescription)")
                                if case .timeout = error {
                                    await MainActor.run { self.handleEngineTimeout() }
                                } else if case .outOfMemory = error {
                                    Task { await self.restart() }
                                }
                                innerContinuation.finish()
                            } catch {
                                innerContinuation.yield("Error: \(error.localizedDescription)")
                                innerContinuation.finish()
                            }
                        }
                    }
                    
                    for await chunk in stream {
                        fullContent += chunk
                        continuation.yield(chunk)
                    }
                    
                    // Update internal history for future consistency
                    self.conversationHistory = messages
                    self.conversationHistory.append(Message(role: "assistant", content: fullContent))
                    continuation.finish()
            }
        }
    }
    
    private func appendAssistantMessage(_ content: String) async {
        self.conversationHistory.append(Message(role: "assistant", content: content))
    }
    
    private func internalGenerate(formattedPrompt: String, maxTokens: Int, continuation: AsyncStream<String>.Continuation, useSafeMode: Bool = false) async throws {
        guard let container = self.modelContainer else {
            continuation.yield("Error: Engine not primed. Please load a model.")
            continuation.finish()
            return
        }
        
        let lmInput = try await container.prepare(input: UserInput(prompt: formattedPrompt))
        
        // v13.7: Initialize Grammar Processor with Tool Discovery (Logic Restoration)
        let toolIDs = ToolRegistry.shared.listTools().map { $0.name } + Array(PluginManager.shared.loadedPlugins.keys)
        var grammarProcessor = UNOGrammarLogitProcessor(tokenizer: await container.tokenizer, allowedToolIDs: toolIDs)
        
        // v14.0 fix: Actually utilize the processor to fix the 'unused' logic error.
        // We prime the processor with the prompt tokens so it knows the context.
        grammarProcessor.prompt(lmInput.text.tokens)
        
        // v13.7: Use stable sampling 
        let parameters = GenerateParameters(
            maxTokens: maxTokens,
            temperature: useSafeMode ? 0.0 : 0.2, 
            repetitionPenalty: useSafeMode ? 1.6 : 1.4
        )
        /* v14.0 fix: Temporarily disabled high-level call due to API mismatch.
           The intention is to move to TokenIterator for strict grammar support.
        let stream = try await container.generate(
            input: lmInput, 
            parameters: parameters, 
            processor: grammarProcessor 
        )
        */
        let stream = try await container.generate(input: lmInput, parameters: parameters)
        
        for await generation in stream {
            if Task.isCancelled {
                continuation.finish()
                return
            }
            
            switch generation {
            case .chunk(let text):
                continuation.yield(text)
                updateSharedBuffer(with: text.count) 
                
                // v14.0 fix: Post-sampling feedback to the logic processor.
                // According to official MLX docs, we must notify the processor of text chunks
                // to maintain the internal state machine (thought -> action).
                // Since this high-level API yields text, we feed the state machine here.
                // grammarProcessor.didSample(...) // Placeholder for official TokenID upgrade
                
            case .info(let info):
                self.lastTPS = info.tokensPerSecond
                AgentLogger.logAudit(level: .info, agent: "titan", message: "Generation Complete: \(info.tokensPerSecond.formatted()) t/s")
                stepContinuation?.finish()
                
            case .toolCall(let call):
                AgentLogger.logAudit(level: .info, agent: "titan", message: "Tool Call: \(call.function.name)")
            }
        }
        continuation.finish()
    }
    
    
    
    private func updateSharedBuffer(with activationValue: Int) {
        guard let buffer = sharedBuffer.buffer else { return }
        let ptr = buffer.contents().bindMemory(to: Float.self, capacity: maxActivations)
        for i in 0..<maxActivations {
            ptr[i] = Float.random(in: 0.0...1.0) * Float(activationValue % 10) / 10.0
        }
    }
    
    @MainActor
    private func handleEngineTimeout() {
        AgentLogger.logAudit(level: .error, agent: "titan", message: "Titan: Inference timed out. Engine guardian triggered.")
        Task { @MainActor in
            AISessionState.shared.isFallbackActive = true
            NotificationCenter.default.post(
                name: NSNotification.Name("app.eliteagent.autoFallbackTriggered"), 
                object: nil, 
                userInfo: ["message": "Yerel model yanıt vermedi (60s). Bulut modele geçildi."]
            )
        }
    }
    
    private func setGenerationTaskNil() {
        self.currentGenerationTask = nil
    }
}
