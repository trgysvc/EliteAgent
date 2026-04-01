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
        AgentLogger.logAudit(level: .info, agent: "orchestrator", message: "Titan: Initializing Qwen via MLXLLM...")
        
        // Using MLXLMCommon global factory to load model container from directory
        self.modelContainer = try await loadModelContainer(directory: url)
        AgentLogger.logAudit(level: .info, agent: "orchestrator", message: "Titan: Intelligence Ready.")
    }
    
    public func generate(prompt: String, maxTokens: Int = 100) -> AsyncStream<String> {
        return AsyncStream(String.self) { continuation in
            Task {
                guard let container = self.modelContainer else {
                    continuation.yield("Error: Engine not primed.")
                    continuation.finish()
                    return
                }
                
                // Qwen 2.5 ChatML format specialization
                let formattedPrompt = "<|im_start|>system\nYou are EliteAgent, a high-performance assistant.<|im_end|>\n<|im_start|>user\n\(prompt)<|im_end|>\n<|im_start|>assistant\n"
                
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
                    AgentLogger.logAudit(level: .error, agent: "titan", message: "Generation failed: \(error.localizedDescription)")
                    continuation.yield("Error: Generation failed.")
                    continuation.finish()
                }
            }
        }
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
