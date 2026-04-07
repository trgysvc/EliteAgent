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
        
        MLX.Memory.cacheLimit = Int(ProcessInfo.processInfo.physicalMemory / 2)
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
                            let response = try await bridge.complete(request)
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
                        let response = try await bridge.complete(request)
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
                        let response = try await cloud.complete(request)
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
    
    public func generate(messages: [Message], systemPrompt: String? = nil, maxTokens: Int = 500) -> AsyncStream<String> {
        return AsyncStream(String.self) { continuation in
            self.currentGenerationTask = Task { [self] in
                // Use the last message content for language detection
                let lastContent = messages.last?.content ?? ""
                let languageInstruction = InferenceActor.buildLanguageInstruction(for: lastContent)
                
                let finalSystemPrompt = """
                \(systemPrompt ?? "You are EliteAgent, a powerful AI assistant running locally on Apple Silicon.")
                \(languageInstruction)
                ### SYSTEM DIRECTIVE: SÖYLEME, YAP!
                Döküman okuduğunda veya dosya yazdığında kullanıcıya \"Yaptım\" demek yerine ÖNCE mutlaka ilgili aracı (tool) çağır.
                """
                
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
                let maxTokensToCapture = maxTokens
                
                    var fullContent = ""
                    let stream: AsyncStream<String> = AsyncStream(String.self) { innerContinuation in
                        Task {
                            do {
                                // v9.7: Wrap in Guardian for Timeout, OOM and Thermal protection.
                                try await MLXEngineGuardian.shared.execute { [self] in
                                    try await self.internalGenerate(formattedPrompt: promptToCapture, maxTokens: maxTokensToCapture, continuation: innerContinuation)
                                }
                            } catch let error as EngineError {
                                innerContinuation.yield("⚠️ Engine Error: \(error.localizedDescription)")
                                if case .timeout = error {
                                    handleEngineTimeout()
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
    
    private func internalGenerate(formattedPrompt: String, maxTokens: Int, continuation: AsyncStream<String>.Continuation) async throws {
        guard let container = self.modelContainer else {
            continuation.yield("Error: Engine not primed. Please load a model.")
            continuation.finish()
            return
        }
        
        let bucketSize = 512 * 4 
        let paddedPrompt = formattedPrompt.padding(toLength: ((formattedPrompt.count / bucketSize) + 1) * bucketSize, withPad: " ", startingAt: 0)
        
        let lmInput = try await container.prepare(input: UserInput(prompt: paddedPrompt))
        let parameters = GenerateParameters(maxTokens: maxTokens)
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
    
    private static func buildLanguageInstruction(for prompt: String) -> String {
        let turkishChars = CharacterSet(charactersIn: "şğüöçıŞĞÜÖÇİ")
        let hasTurkish = prompt.unicodeScalars.contains { turkishChars.contains($0) }
        return hasTurkish ? "CRITICAL: Respond ONLY in Turkish." : "CRITICAL: Match user's language."
    }
    
    private func updateSharedBuffer(with activationValue: Int) {
        guard let buffer = sharedBuffer.buffer else { return }
        let ptr = buffer.contents().bindMemory(to: Float.self, capacity: maxActivations)
        for i in 0..<maxActivations {
            ptr[i] = Float.random(in: 0.0...1.0) * Float(activationValue % 10) / 10.0
        }
    }
    
    private func handleEngineTimeout() {
        AgentLogger.logAudit(level: .error, agent: "titan", message: "Critical: Engine Hang (60s). Switching to Cloud fallback.")
        Task { @MainActor in
            AISessionState.shared.isFallbackActive = true
            NotificationCenter.default.post(
                name: NSNotification.Name("app.eliteagent.autoFallbackTriggered"), 
                object: nil, 
                userInfo: ["message": "Yerel model yanıt vermedi (60s). Bulut modele geçildi."]
            )
        }
    }
}
