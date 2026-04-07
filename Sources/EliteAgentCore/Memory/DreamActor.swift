import Foundation
import OSLog

/// A background actor for consolidating long-term memory.
/// Implements the "Dream" pattern from EliteAgent v10.0 architecture.
/// Hardened with TokenBudget and EnergyState awareness.
public actor DreamActor {
    public static let shared = DreamActor()
    
    private let logger = Logger(subsystem: "com.elite.agent", category: "DreamEngine")
    private let memoryLimit = 5000 // Chars before consolidation
    
    private init() {}
    
    /// Triggers a consolidation session if conditions (Token, Energy, Content) are met.
    public func consolidateIfNeeded(memoryAgent: MemoryAgent, cloudProvider: CloudProvider) async {
        // 1. Check Energy & Thermal State
        let thermalState = ProcessInfo.processInfo.thermalState
        if thermalState == .serious || thermalState == .critical {
            logger.warning("Dream consolidation skipped due to thermal pressure: \(thermalState.rawValue)")
            return
        }
        
        // 2. Check Token Budget
        let canProceed = await TokenBudgetActor.shared.requestApproval(estimatedTokens: 1000)
        guard canProceed else {
            logger.warning("Dream consolidation skipped: Token budget exceeded.")
            return
        }
        
        // 3. Orient: Gather candidates for consolidation
        let l1 = await memoryAgent.getL1()
        let l1Text = l1.map { "[\($0.role)]: \($0.content)" }.joined(separator: "\n")
        
        guard l1Text.count > memoryLimit else { return }
        
        logger.info("Starting Dream Consolidation (Content Size: \(l1Text.count) chars)")
        
        do {
            // 4. Consolidate: Ask LLM to extract facts and core knowledge
            let consolidationPrompt = """
            Analyze the following conversation history and extract core facts, project decisions, 
            and technical knowledge. Format as a concise, structured markdown report.
            Keep specific paths, IDs, and final decisions. 
            Ignore casual banter or intermediate errors that were resolved.
            """
            
            let request = CompletionRequest(
                taskID: "dream-\(UUID().uuidString.prefix(8))",
                systemPrompt: consolidationPrompt,
                messages: [Message(role: "user", content: "Memory Context:\n\n\(l1Text)")],
                maxTokens: 1000,
                sensitivityLevel: .public,
                complexity: 2
            )
            
            let response = try await cloudProvider.complete(request)
            
            // v10.0: Net-Savings Validation (25% Threshold)
            let rawLogTokens = l1Text.count / 4
            let summaryTokens = response.tokensUsed.completion
            let savingsRatio = Double(summaryTokens) / Double(max(1, rawLogTokens))
            
            if savingsRatio > 0.25 {
                logger.warning("Dream consolidation aborted: Net-negative savings (\(Int(savingsRatio * 100))% ratio > 25% threshold).")
                try logSkipToDiff(reason: "net_negative_savings (ratio: \(Int(savingsRatio * 100))%)")
                return
            }
            
            // 5. Persist: Versioned Memory
            try saveVersionedMemory(content: response.content)
            
            // Record usage
            await TokenBudgetActor.shared.recordUsage(tokens: response.tokensUsed.total, cost: response.costUSD)
            
            logger.info("Dream Consolidation Successful. Versioned memory updated.")
        } catch {
            logger.error("Consolidation Failed: \(error.localizedDescription)")
        }
    }
    
    private func saveVersionedMemory(content: String) throws {
        let paths = PathConfiguration.shared
        let memoryDir = paths.applicationSupportURL.appendingPathComponent("MemoryBank")
        try FileManager.default.createDirectory(at: memoryDir, withIntermediateDirectories: true)
        
        let existingFiles = try FileManager.default.contentsOfDirectory(at: memoryDir, includingPropertiesForKeys: nil)
        let versions = existingFiles.compactMap { url -> Int? in
            let name = url.lastPathComponent
            if name.hasPrefix("memory_v") && name.hasSuffix(".md") {
                return Int(name.dropFirst(8).dropLast(3))
            }
            return nil
        }
        
        let nextVersion = (versions.max() ?? 0) + 1
        let newMemoryURL = memoryDir.appendingPathComponent("memory_v\(nextVersion).md")
        let diffURL = memoryDir.appendingPathComponent("diff.log")
        
        try content.write(to: newMemoryURL, atomically: true, encoding: .utf8)
        
        let diffEntry = "[\(ISO8601DateFormatter().string(from: Date()))] Created memory_v\(nextVersion).md (Size: \(content.count) chars)\n"
        if let data = diffEntry.data(using: .utf8) {
            if FileManager.default.fileExists(atPath: diffURL.path) {
                let handle = try FileHandle(forWritingTo: diffURL)
                handle.seekToEndOfFile()
                handle.write(data)
                handle.closeFile()
            } else {
                try data.write(to: diffURL)
            }
        }
    }
    
    private func logSkipToDiff(reason: String) throws {
        let paths = PathConfiguration.shared
        let memoryDir = paths.applicationSupportURL.appendingPathComponent("MemoryBank")
        let diffURL = memoryDir.appendingPathComponent("diff.log")
        
        let skipEntry = "[\(ISO8601DateFormatter().string(from: Date()))] SKIPPED: \(reason)\n"
        if let data = skipEntry.data(using: .utf8) {
            if FileManager.default.fileExists(atPath: diffURL.path) {
                let handle = try FileHandle(forWritingTo: diffURL)
                handle.seekToEndOfFile()
                handle.write(data)
                handle.closeFile()
            } else {
                try data.write(to: diffURL)
            }
        }
    }
}
