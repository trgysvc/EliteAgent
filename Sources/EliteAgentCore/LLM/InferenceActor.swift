// EliteAgent Titan Engine - v7.5.4 (Concurrency Safe)
import Foundation
import MLX
import MLXLLM
import MLXLMCommon
import Metal

/// The offline brain of EliteAgent.
public actor InferenceActor {
    public static let shared = InferenceActor()
    
    nonisolated public let sharedBuffer: MetalBufferWrapper
    private let maxActivations = 1024
    
    private var modelContainer: ModelContainer?
    private var maxContextTokens: Int = 16384 // Optimized for 16GB RAM M4
    private var conversationHistory: [Message] = []
    
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
    
    public func clearCache() {
        AgentLogger.logAudit(level: .info, agent: "guard", message: "Memory pressure. Clearing GPU cache.")
        MLX.eval()
        MLX.Memory.clearCache()
    }
    
    public func unloadModel() async {
        AgentLogger.logAudit(level: .info, agent: "orchestrator", message: "Titan: Unloading current model...")
        self.modelContainer = nil
        self.clearCache()
        
        await MainActor.run {
            ModelSetupManager.shared.isModelReady = false
            ModelSetupManager.shared.loadState = .idle
        }
    }
    
    public func clearContext() {
        AgentLogger.logAudit(level: .info, agent: "titan", message: "Titan: Context invalidated & history cleared (Tokenizer switch).")
        self.conversationHistory.removeAll()
        // MLXLLM ModelContainer handles internal state, resetting container ensures fresh KV cache
    }
    
    public func loadModel(at url: URL) async throws {
        AgentLogger.logAudit(level: .info, agent: "orchestrator", message: "Titan: Initializing Model via MLXLMCommon at \(url.lastPathComponent)...")
        
        // Ensure clean slate
        MLX.eval()
        MLX.Memory.clearCache()
        
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
    
    public func generate(prompt: String, systemPrompt: String? = nil, maxTokens: Int = 100) -> AsyncStream<String> {
        return AsyncStream(String.self) { continuation in
            Task { [self] in
                let languageInstruction = InferenceActor.buildLanguageInstruction(for: prompt)
                let agenticDirectives = """
                ### SYSTEM DIRECTIVE: SÖYLEME, YAP!
                Döküman okuduğunda veya dosya yazdığında kullanıcıya "Yaptım" demek yerine ÖNCE mutlaka ilgili aracı (tool) çağır.
                """
                
                let finalSystemPrompt = """
                \(systemPrompt ?? "You are EliteAgent, a powerful AI assistant running locally on Apple Silicon.")
                \(languageInstruction)
                \(agenticDirectives)
                """
                let formattedPrompt = "<|im_start|>system\n\(finalSystemPrompt)<|im_end|>\n<|im_start|>user\n\(prompt)<|im_end|>\n<|im_start|>assistant\n"
                
                do {
                    try await self.internalGenerate(formattedPrompt: formattedPrompt, maxTokens: maxTokens, continuation: continuation)
                } catch {
                    AgentLogger.logAudit(level: .error, agent: "titan", message: "Generation failed: \(error.localizedDescription)")
                    continuation.yield("Error: Generation failed.")
                    continuation.finish()
                }
            }
        }
    }
    
    private func internalGenerate(formattedPrompt: String, maxTokens: Int, continuation: AsyncStream<String>.Continuation) async throws {
        guard let container = self.modelContainer else {
            continuation.yield("Error: Engine not primed.")
            continuation.finish()
            return
        }
        
        let generationStart = Date()
        
        // v7.5.4: Bucketed Sequence Length (The core performance fix for the 180s delay)
        // Pad to nearest 512 tokens (approx 2048 chars) to stabilize Metal graph shape.
        let bucketSize = 512 * 4 
        let paddedPrompt = formattedPrompt.padding(toLength: ((formattedPrompt.count / bucketSize) + 1) * bucketSize, withPad: " ", startingAt: 0)
        
        AgentLogger.logAudit(level: .info, agent: "titan", message: "Titan: Encoding & Prefilling bucket (\(paddedPrompt.count / bucketSize) blocks)...")
        emitStep(.step(name: "Reasoning & Context Prep", status: .active, icon: "brain.headset"))
        let encodingStart = Date()
        
        // Prepare (Prefill)
        let lmInput = try await container.prepare(input: UserInput(prompt: paddedPrompt))
        AgentLogger.logAudit(level: .info, agent: "titan", message: "Titan: Encoding complete (\(String(format: "%.2fs", Date().timeIntervalSince(encodingStart)))). Starting generation...")

        let parameters = GenerateParameters(maxTokens: maxTokens)
        let stream = try await container.generate(input: lmInput, parameters: parameters)
        
        var firstToken = true
        for await generation in stream {
            if firstToken {
                firstToken = false
                let ttft = Date().timeIntervalSince(generationStart)
                AgentLogger.logAudit(level: .info, agent: "titan", message: "Titan: First token received (TTFT: \(String(format: "%.2fs", ttft)))")
                emitStep(.step(name: "Response Generation", status: .active, icon: "text.bubble.fill"))
            }
            
            switch generation {
            case .chunk(let text):
                continuation.yield(text)
                updateSharedBuffer(with: text.count) 
                
                let currentState = ProcessInfo.processInfo.thermalState
                if currentState == .serious { try? await Task.sleep(nanoseconds: 10_000_000) }
                else if currentState == .critical { try? await Task.sleep(nanoseconds: 50_000_000) }
                
            case .info(let info):
                let ttft = Date().timeIntervalSince(generationStart)
                AgentLogger.logAudit(level: .info, agent: "titan", message: "Generation Complete: \(info.tokensPerSecond.formatted()) t/s (TTFT: \(String(format: "%.2fs", ttft)))")
                emitStep(.step(name: "Task Complete", status: .success, icon: "checkmark.seal.fill"))
                stepContinuation?.finish()
                
            case .toolCall(let call):
                AgentLogger.logAudit(level: .info, agent: "titan", message: "Tool Call Detected: \(call.function.name)")
                emitStep(.step(name: "Executing: \(call.function.name)", status: .active, icon: "wrench.and.screwdriver.fill"))
            }
        }
        continuation.finish()
    }
    
    private static func buildLanguageInstruction(for prompt: String) -> String {
        let turkishChars = CharacterSet(charactersIn: "şğüöçıŞĞÜÖÇİ")
        let hasTurkish = prompt.unicodeScalars.contains { turkishChars.contains($0) }
        if hasTurkish { return "CRITICAL RULE: Respond ONLY in Turkish." }
        return "CRITICAL RULE: Always respond in the EXACT same language the user is writing in."
    }
    
    private func updateSharedBuffer(with activationValue: Int) {
        guard let buffer = sharedBuffer.buffer else { return }
        let ptr = buffer.contents().bindMemory(to: Float.self, capacity: maxActivations)
        for i in 0..<maxActivations {
            ptr[i] = Float.random(in: 0.0...1.0) * Float(activationValue % 10) / 10.0
        }
    }
}
