// EliteAgent Titan Engine - v3.1
import Foundation
import MLX
import MLXNN
import MLXRandom
import Metal

/// The offline brain of EliteAgent.
/// Manages local MLX model sessions and bridges activations to the GPU for visualization.
public actor InferenceActor {
    public static let shared = InferenceActor()
    
    // Unified Memory Bridge for Neural Sight
    nonisolated public let sharedBuffer: MetalBufferWrapper
    private let maxActivations = 1024
    
    private var mistral: MistralModel?
    private var tokenizer: BPETokenizer?
    
    private init() {
        // Initialize shared buffer for Metal visualization (Zero-copy)
        let device = MTLCreateSystemDefaultDevice()
        let size = maxActivations * MemoryLayout<Float>.size
        let buffer = device?.makeBuffer(length: size, options: .storageModeShared)
        self.sharedBuffer = MetalBufferWrapper(buffer)
        
        // Optimize GPU cache for 8GB/16GB devices
        let mem = ProcessInfo.processInfo.physicalMemory
        let limit = mem / 2 // Use 50% of RAM as cache limit
        MLX.Memory.cacheLimit = Int(limit)
        
        // Setup monitoring asynchronously to avoid init isolation issues
        Task {
            await setupMemoryMonitoring()
        }
    }
    
    private func setupMemoryMonitoring() {
        // Listen for system memory pressure to clear cache
        let source = DispatchSource.makeMemoryPressureSource(eventMask: [.warning, .critical], queue: .global())
        source.setEventHandler { [weak self] in
            Task { [weak self] in
                await self?.clearCache()
            }
        }
        source.resume()
    }
    
    public func clearCache() {
        AgentLogger.logAudit(level: .info, agent: "guard", message: "System memory pressure detected. Clearing MLX GPU cache.")
        MLX.Memory.clearCache()
    }
    
    public func loadModel(at url: URL) async throws {
        AgentLogger.logAudit(level: .info, agent: "orchestrator", message: "Titan: Initializing Real MLX Brain from \(url.path)...")
        
        let config = MistralConfig.mistral7B
        let model = MistralModel(config)
        
        let state = try ModelLoader.loadState(from: url)
        ModelLoader.apply(state: state, to: model)
        
        let tokenizer = try BPETokenizer.load(from: url)
        
        self.mistral = model
        self.tokenizer = tokenizer
        
        AgentLogger.logAudit(level: .info, agent: "orchestrator", message: "Titan: Local Intelligence is READY.")
    }
    
    /// Generates tokens as an AsyncStream to ensure thread safety with MLXArray mutations.
    public func generate(prompt: String, maxTokens: Int = 100) -> AsyncStream<String> {
        return AsyncStream(String.self) { continuation in
            Task {
                guard let model = self.mistral, let tokenizer = self.tokenizer else {
                    continuation.yield("Error: Model not loaded.")
                    continuation.finish()
                    return
                }
                
                var tokens = tokenizer.encode(text: prompt)
                let cache = (0..<MistralConfig.mistral7B.numHiddenLayers).map { _ in KVCache() }
                
                for _ in 0..<maxTokens {
                    let input = MLXArray(tokens.map { Int32($0) }).reshaped(1, -1)
                    let logits = model(input, cache: cache)
                    
                    let lastLogits = logits[0, -1, 0...]
                    let newTokenID = argMax(lastLogits).item(Int.self)
                    
                    if newTokenID == 2 { break }
                    
                    tokens = [newTokenID]
                    for c in cache { c.offset += 1 }
                    
                    let newText = tokenizer.decode(tokens: [newTokenID])
                    updateSharedBuffer(with: lastLogits)
                    
                    continuation.yield(newText)
                }
                continuation.finish()
            }
        }
    }
    
    private func updateSharedBuffer(with data: MLXArray) {
        guard let buffer = sharedBuffer.buffer else { return }
        let ptr = buffer.contents().bindMemory(to: Float.self, capacity: maxActivations)
        
        let normalized = MLX.sigmoid(data[0..<maxActivations].asType(.float32))
        let values = normalized.asArray(Float.self)
        
        for i in 0..<min(maxActivations, values.count) {
            ptr[i] = values[i]
        }
    }
}
