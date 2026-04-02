// EliteAgent Titan Engine - v7.0 (Qwen-Ready)
import Foundation
import MLX
import MLXLLM
import MLXLMCommon
import Metal

/// The offline brain of EliteAgent.
/// Manages local MLX model sessions and bridges activations to the GPU for visualization.
public actor InferenceActor {
    public static let shared = InferenceActor()
    
    // Unified Memory Bridge for Neural Sight
    nonisolated public let sharedBuffer: MetalBufferWrapper
    private let maxActivations = 1024
    
    private var modelContainer: ModelContainer?
    private var maxContextTokens: Int = 16384 // Optimized for 16GB RAM M4
    
    private init() {
        let device = MTLCreateSystemDefaultDevice()
        let size = maxActivations * MemoryLayout<Float>.size
        let buffer = device?.makeBuffer(length: size, options: .storageModeShared)
        self.sharedBuffer = MetalBufferWrapper(buffer)
        
        // Cache limit: 50% for high-performance runs
        MLX.Memory.cacheLimit = Int(ProcessInfo.processInfo.physicalMemory / 2)
        
        // v7.4.0 CRITICAL FIX: Force linker to keep MLXLLM's TrampolineModelFactory in the binary.
        // Without this direct reference, Swift's dead-code elimination removes the class,
        // causing NSClassFromString("MLXLLM.TrampolineModelFactory") to return nil at runtime,
        // which results in the 'noModelFactoryAvailable' error.
        _ = LLMModelFactory.shared
        
        Task {
            await setupResourceMonitoring()
        }
    }
    
    private func setupResourceMonitoring() {
        // Memory Pressure
        let source = DispatchSource.makeMemoryPressureSource(eventMask: [.warning, .critical], queue: .global())
        source.setEventHandler { [weak self] in
            Task { [weak self] in await self?.clearCache() }
        }
        source.resume()
        
        // Thermal State Notification
        NotificationCenter.default.addObserver(forName: ProcessInfo.thermalStateDidChangeNotification, object: nil, queue: .main) { _ in
            print("[Thermal] Monitoring: \(ProcessInfo.processInfo.thermalState)")
        }
    }
    
    public func clearCache() {
        AgentLogger.logAudit(level: .info, agent: "guard", message: "Memory pressure. Clearing GPU cache.")
        MLX.Memory.clearCache()
    }
    
    public func loadModel(at url: URL) async throws {
        AgentLogger.logAudit(level: .info, agent: "orchestrator", message: "Titan: Initializing Model via MLXLMCommon at \(url.lastPathComponent)...")
        
        // Update global load state
        await MainActor.run {
            ModelSetupManager.shared.loadState = .transferringToVRAM
            ModelSetupManager.shared.isModelReady = false
        }
        
        // 1. Pre-flight Check: Directory Existence
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir), isDir.boolValue else {
            let errorMsg = "Titan Error: Model directory not found at \(url.path). Please re-download."
            await updateFailedState(errorMsg: errorMsg)
            throw ProviderError.networkError(errorMsg)
        }
        
        // 2. Load via explicit LLMModelFactory to guarantee correct factory is used
        do {
            let config = ModelConfiguration(directory: url)
            self.modelContainer = try await LLMModelFactory.shared.loadContainer(configuration: config)
            
            await MainActor.run {
                ModelSetupManager.shared.loadState = .ready
                ModelSetupManager.shared.isModelReady = true
            }
            AgentLogger.logAudit(level: .info, agent: "orchestrator", message: "Titan: Intelligence Ready.")
        } catch {
            let detailedError: String
            if error.localizedDescription.contains("noModelFactoryAvailable") {
                detailedError = "Titan Error: Architecture mismatch or missing factory for \(url.lastPathComponent). Manual registration required."
            } else if error.localizedDescription.contains("out of memory") {
                detailedError = "Titan Error: Insufficient VRAM to load \(url.lastPathComponent). Close other GPU apps."
            } else {
                detailedError = "Titan Error: \(error.localizedDescription)"
            }
            
            await updateFailedState(errorMsg: detailedError)
            throw error
        }
    }
    
    private func updateFailedState(errorMsg: String) async {
        await MainActor.run {
            ModelSetupManager.shared.loadState = .failed
            ModelSetupManager.shared.isModelReady = false
        }
        AgentLogger.logAudit(level: .error, agent: "orchestrator", message: errorMsg)
    }
    
    public func generate(prompt: String, systemPrompt: String? = nil, maxTokens: Int = 100) -> AsyncStream<String> {
        return AsyncStream(String.self) { continuation in
            Task {
                guard let container = self.modelContainer else {
                    await MainActor.run {
                        continuation.yield("Error: Engine not primed.")
                        continuation.finish()
                    }
                    return
                }
                
                // v7.6.0: Strict Agentic Prompt with 1-Shot Example to prevent 'Hallucination of Action'
                let agenticDirectives = """
                ### SYSTEM DIRECTIVE: SÖYLEME, YAP! (Don't tell, DO!)
                Döküman okuduğunda veya dosya yazdığında kullanıcıya "Yaptım" demek yerine ÖNCE mutlaka ilgili aracı (tool) çağır.
                
                ### TOOL CALL FORMAT (ZORUNLU):
                Bir araç kullanman gerekiyorsa, <final> bloğu içine SADECE JSON objesini koy.
                Örnek: Bir dosyayı özetleyip kaydetmen istendiğinde:
                
                <think>Dosyayı özetledim. Şimdi 'ozet.md' olarak 'AI Works' klasörüne kaydedeceğim.</think>
                <final>
                {
                  "tool": "write_file",
                  "params": {
                    "path": "AI Works/ozet.md",
                    "content": "# Özet\\n..."
                  }
                }
                </final>
                """
                
                // v7.4.1 Language Mirroring: Detect user language and enforce it in system prompt
                let languageInstruction = InferenceActor.buildLanguageInstruction(for: prompt)
                
                let finalSystemPrompt = """
                \(systemPrompt ?? "You are EliteAgent, a powerful AI assistant running locally on Apple Silicon.")
                \(languageInstruction)
                \(agenticDirectives)
                """
                let formattedPrompt = "<|im_start|>system\n\(finalSystemPrompt)<|im_end|>\n<|im_start|>user\n\(prompt)<|im_end|>\n<|im_start|>assistant\n"
                
                do {
                    // 1. Prepare Input
                    let lmInput = try await container.prepare(input: UserInput(prompt: formattedPrompt))
                    let parameters = GenerateParameters(maxTokens: maxTokens)
                    
                    // 2. Start Async Generation Stream
                    let stream = try await container.generate(input: lmInput, parameters: parameters)
                    
                    for await generation in stream {
                        switch generation {
                        case .chunk(let text):
                            continuation.yield(text)
                            
                            // Real-time Visualizer sync (simulated activation pulse)
                            updateSharedBuffer(with: text.count) 
                            
                            // 3. Adaptive Thermal Throttling
                            let currentState = ProcessInfo.processInfo.thermalState
                            if currentState == .serious {
                                try? await Task.sleep(nanoseconds: 10_000_000) // 10ms delay
                            } else if currentState == .critical {
                                try? await Task.sleep(nanoseconds: 50_000_000) // 50ms heavy throttle
                            }
                            
                        case .info(let info):
                            AgentLogger.logAudit(level: .info, agent: "titan", message: "Generation Complete: \(info.tokensPerSecond.formatted()) t/s")
                            
                        case .toolCall(let call):
                            AgentLogger.logAudit(level: .info, agent: "titan", message: "Tool Call Detected: \(call.function.name)")
                        }
                    }
                    
                    continuation.finish()
                } catch {
                    let msg = error.localizedDescription
                    await MainActor.run {
                        AgentLogger.logAudit(level: .error, agent: "titan", message: "Generation failed: \(msg)")
                        continuation.yield("Error: Generation failed.")
                        continuation.finish()
                    }
                }
            }
        }
    }
    
    /// Detects the language of the user's prompt and returns a strict instruction
    /// that forces the LLM to respond in the same language.
    private static func buildLanguageInstruction(for prompt: String) -> String {
        // Detect Turkish script characters
        let turkishChars = CharacterSet(charactersIn: "şğüöçıŞĞÜÖÇİ")
        let hasTurkish = prompt.unicodeScalars.contains { turkishChars.contains($0) }
        
        if hasTurkish {
            return "CRITICAL RULE: The user is writing in Turkish. You MUST respond ONLY in Turkish. Do NOT use any other language including Chinese, English, or any other. Your entire response must be in Turkish."
        }
        
        // Detect Cyrillic (Russian etc.)
        let cyrillicRange = Unicode.Scalar(0x0400)!...Unicode.Scalar(0x04FF)!
        let hasCyrillic = prompt.unicodeScalars.contains { cyrillicRange.contains($0) }
        if hasCyrillic {
            return "CRITICAL RULE: Respond ONLY in Russian (Cyrillic). Do not use any other language."
        }
        
        // Detect Arabic script
        let arabicRange = Unicode.Scalar(0x0600)!...Unicode.Scalar(0x06FF)!
        let hasArabic = prompt.unicodeScalars.contains { arabicRange.contains($0) }
        if hasArabic {
            return "CRITICAL RULE: Respond ONLY in Arabic. Do not use any other language."
        }
        
        // Default: mirror the user's language (catches English and others)
        return "CRITICAL RULE: Always respond in the EXACT same language the user is writing in. If they write in English, respond in English. If they write in another language, match it exactly. NEVER respond in Chinese unless the user wrote in Chinese."
    }
    
    private func updateSharedBuffer(with activationValue: Int) {
        guard let buffer = sharedBuffer.buffer else { return }
        let ptr = buffer.contents().bindMemory(to: Float.self, capacity: maxActivations)
        
        // Push pulse data during generation to drive the visualizer
        for i in 0..<maxActivations {
            ptr[i] = Float.random(in: 0.0...1.0) * Float(activationValue % 10) / 10.0
        }
    }
}
