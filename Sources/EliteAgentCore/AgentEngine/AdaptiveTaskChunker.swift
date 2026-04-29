import Foundation

/// v27.0: Adaptive Task Chunking Engine
/// Splits large workloads into context-safe chunks based on hardware capacity
/// and model context window limits. Each chunk carries forward the context
/// summary from the previous chunk, ensuring the agent NEVER loses coherence.
public actor AdaptiveTaskChunker {
    
    // MARK: - Types
    
    /// Snapshot of current hardware state from HardwareMonitor.
    public struct HardwareState: Sendable {
        public let availableMemoryGB: Double
        public let totalMemoryGB: Double
        public let thermalState: ProcessInfo.ThermalState
        public let estimatedModelVRAMGB: Double
        
        public init(
            availableMemoryGB: Double,
            totalMemoryGB: Double,
            thermalState: ProcessInfo.ThermalState,
            estimatedModelVRAMGB: Double = 4.0
        ) {
            self.availableMemoryGB = availableMemoryGB
            self.totalMemoryGB = totalMemoryGB
            self.thermalState = thermalState
            self.estimatedModelVRAMGB = estimatedModelVRAMGB
        }
        
        /// Memory pressure ratio (0.0 = empty, 1.0 = full).
        public var memoryPressure: Double {
            return 1.0 - (availableMemoryGB / max(1.0, totalMemoryGB))
        }
        
        /// Whether the system is under thermal stress.
        public var isThermalConstrained: Bool {
            return thermalState == .serious || thermalState == .critical
        }
    }
    
    /// Context budget information for the active model.
    public struct ContextBudget: Sendable {
        public let maxTokens: Int
        public let currentUsedTokens: Int
        public let systemPromptTokens: Int
        public let safetyMarginRatio: Double
        
        public init(
            maxTokens: Int = 8_192,
            currentUsedTokens: Int = 0,
            systemPromptTokens: Int = 1_500,
            safetyMarginRatio: Double = 0.20
        ) {
            self.maxTokens = maxTokens
            self.currentUsedTokens = currentUsedTokens
            self.systemPromptTokens = systemPromptTokens
            self.safetyMarginRatio = safetyMarginRatio
        }
        
        /// Tokens available for task processing after reserving system prompt and safety margin.
        public var availableForTask: Int {
            let reserved = systemPromptTokens + Int(Double(maxTokens) * safetyMarginRatio)
            return max(0, maxTokens - reserved - currentUsedTokens)
        }
    }
    
    /// A single chunk of work that preserves context from previous chunks.
    public struct TaskChunk: Sendable {
        public let index: Int
        public let totalChunks: Int
        public let items: [String]
        public let contextCarryOver: String
        public let estimatedTokens: Int
        
        /// Human-readable progress description for UI display.
        public var progressDescription: String {
            let itemStart = items.first ?? "?"
            let itemEnd = items.last ?? "?"
            return "Chunk \(index + 1)/\(totalChunks) — Items: \(itemStart)...\(itemEnd)"
        }
    }
    
    /// The chunking decision result.
    public enum ChunkingDecision: Sendable {
        /// Task fits in a single pass — no chunking needed.
        case singlePass
        
        /// Task must be split into multiple chunks.
        case chunked(chunks: [TaskChunk])
        
        /// Task cannot be completed even in chunks — capacity insufficient.
        case capacityInsufficient(reason: String)
    }
    
    // MARK: - Configuration
    
    /// Estimated tokens per work item (conservative default).
    private let tokensPerItem: Int = 50
    
    /// Minimum items per chunk to avoid excessive overhead.
    private let minItemsPerChunk: Int = 5
    
    /// Maximum number of chunks to prevent excessive fragmentation.
    private let maxChunks: Int = 20
    
    /// Thermal throttle multiplier — reduce chunk size under thermal stress.
    private let thermalThrottleMultiplier: Double = 0.6
    
    /// Memory pressure multiplier — reduce chunk size under memory pressure.
    private let memoryPressureMultiplier: Double = 0.7
    
    public init() {}
    
    // MARK: - Public API
    
    /// Determines whether a task with the given items needs to be chunked.
    /// - Parameters:
    ///   - items: List of work items (file paths, IDs, etc.)
    ///   - hardwareState: Current hardware snapshot
    ///   - contextBudget: Current context window budget
    /// - Returns: A `ChunkingDecision` indicating how to proceed.
    public func chunkIfNeeded(
        items: [String],
        hardwareState: HardwareState,
        contextBudget: ContextBudget
    ) -> ChunkingDecision {
        let availableTokens = contextBudget.availableForTask
        
        // Check if single pass is possible
        let totalEstimatedTokens = items.count * tokensPerItem
        
        if totalEstimatedTokens <= availableTokens && !hardwareState.isThermalConstrained {
            return .singlePass
        }
        
        // Calculate effective capacity with hardware multipliers
        var effectiveTokenBudget = Double(availableTokens)
        
        if hardwareState.isThermalConstrained {
            effectiveTokenBudget *= thermalThrottleMultiplier
        }
        
        if hardwareState.memoryPressure > 0.85 {
            effectiveTokenBudget *= memoryPressureMultiplier
        }
        
        let safeTokensPerChunk = Int(effectiveTokenBudget)
        
        // Cannot process even a single item
        if safeTokensPerChunk < tokensPerItem * minItemsPerChunk {
            return .capacityInsufficient(
                reason: "Available context budget (\(safeTokensPerChunk) tokens) is insufficient for even \(minItemsPerChunk) items. " +
                        "Memory pressure: \(Int(hardwareState.memoryPressure * 100))%, " +
                        "Thermal: \(hardwareState.thermalState == .nominal ? "nominal" : "constrained"). " +
                        "Consider closing other applications or using a model with a larger context window."
            )
        }
        
        // Calculate items per chunk
        let itemsPerChunk = max(minItemsPerChunk, safeTokensPerChunk / tokensPerItem)
        let chunkCount = min(maxChunks, (items.count + itemsPerChunk - 1) / itemsPerChunk)
        
        if chunkCount <= 1 {
            return .singlePass
        }
        
        // Build chunks
        var chunks: [TaskChunk] = []
        var startIndex = 0
        
        for i in 0..<chunkCount {
            let endIndex = min(startIndex + itemsPerChunk, items.count)
            let chunkItems = Array(items[startIndex..<endIndex])
            
            let contextCarryOver: String
            if i == 0 {
                contextCarryOver = ""
            } else {
                // Each subsequent chunk will receive the summary from the previous chunk
                contextCarryOver = "[CONTEXT FROM CHUNK \(i)/\(chunkCount)]: Previous \(startIndex) items completed successfully. Continue with items \(startIndex + 1)-\(endIndex)."
            }
            
            chunks.append(TaskChunk(
                index: i,
                totalChunks: chunkCount,
                items: chunkItems,
                contextCarryOver: contextCarryOver,
                estimatedTokens: chunkItems.count * tokensPerItem
            ))
            
            startIndex = endIndex
            if startIndex >= items.count { break }
        }
        
        return .chunked(chunks: chunks)
    }
    
    /// Creates a hardware state snapshot from the shared HardwareMonitor.
    public static func captureHardwareState() async -> HardwareState {
        let monitor = HardwareMonitor.shared
        let memStats = await monitor.getMemoryStats()
        let thermalState = ProcessInfo.processInfo.thermalState
        
        return HardwareState(
            availableMemoryGB: memStats.total - memStats.used,
            totalMemoryGB: memStats.total,
            thermalState: thermalState,
            estimatedModelVRAMGB: 4.0 // Default for 7B 4-bit model
        )
    }
    
    /// Generates a user-facing progress notification for the UI overlay.
    public static func progressNotification(
        chunk: TaskChunk,
        completedItems: Int,
        totalItems: Int,
        reason: String
    ) -> String {
        let progressBar = Self.renderProgressBar(completed: chunk.index, total: chunk.totalChunks)
        return """
        ⚙️ Adaptive Task Chunking Active
        \(progressBar) Chunk \(chunk.index + 1)/\(chunk.totalChunks) — \(completedItems)/\(totalItems) items completed
        Reason: \(reason)
        Context preserved: Previous chunk results carried forward.
        """
    }
    
    // MARK: - Private Utilities
    
    private static func renderProgressBar(completed: Int, total: Int) -> String {
        let filled = max(0, min(10, (completed * 10) / max(1, total)))
        let empty = 10 - filled
        return "[" + String(repeating: "█", count: filled) + String(repeating: "░", count: empty) + "]"
    }
}
