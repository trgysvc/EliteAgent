import Foundation
import Combine

public struct MemoryEntry: Codable, Sendable {
    public let role: String
    public let content: String
    public let timestamp: Date
    public init(role: String, content: String, timestamp: Date = Date()) {
        self.role = role
        self.content = content
        self.timestamp = timestamp
    }
}

public struct MemoryThinkBlock: Codable, Sendable {
    public let content: String
    public let timestamp: Date
    public init(content: String, timestamp: Date = Date()) {
        self.content = content
        self.timestamp = timestamp
    }
}

public actor MemoryAgent: AgentProtocol {
    public let agentID: AgentID = .memory
    public private(set) var status: AgentStatus = .idle
    public let preferredProvider: ProviderID = .none
    public let fallbackProviders: [ProviderID] = []
    
    private let bus: SignalBus
    private let vault = ExperienceVault.shared
    private let embedder = EmbeddingService.shared
    
    // L1 Context
    private var l1Context: [MemoryEntry] = []
    private var thinkBuffer: [MemoryThinkBlock] = []
    
    // L2 Storage Paths (Privacy Split - Item 36)
    private let publicL2: URL
    private let internalL2: URL
    private let thinkLogURL: URL
    
    public init(bus: SignalBus, publicURL: URL? = nil, internalURL: URL? = nil) {
        self.bus = bus
        let paths = PathConfiguration.shared
        self.publicL2 = publicURL ?? paths.applicationSupportURL.appendingPathComponent("KNOWLEDGE_BASE_public.md")
        self.internalL2 = internalURL ?? paths.applicationSupportURL.appendingPathComponent("KNOWLEDGE_BASE_internal.md")
        self.thinkLogURL = paths.applicationSupportURL.appendingPathComponent("THINK_LOG.md")
    }
    
    public func receive(_ signal: Signal) async throws {
        if signal.name == "THINK_BLOCK" {
            if let block = try? JSONDecoder().decode(MemoryThinkBlock.self, from: signal.payload) {
                storeThinkBlock(block)
            }
        } else if signal.name == "ROTATE_LOGS" {
            rotateLogsIfNeeded()
        }
    }
    
    public func healthReport() -> AgentHealth {
        return AgentHealth(isHealthy: true, statusMessage: "OK")
    }
    
    public func appendToL1(role: String, content: String) {
        l1Context.append(MemoryEntry(role: role, content: content))
    }
    
    private func appendToFile(url: URL, text: String) {
        let dir = url.deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        if let data = text.data(using: .utf8) {
            if FileManager.default.fileExists(atPath: url.path) {
                if let handle = try? FileHandle(forWritingTo: url) {
                    handle.seekToEndOfFile()
                    handle.write(data)
                    handle.closeFile()
                }
            } else {
                try? data.write(to: url)
            }
        }
    }
    
    public func storeThinkBlock(_ block: MemoryThinkBlock) {
        thinkBuffer.append(block)
        if thinkBuffer.count > 5 {
            let oldest = thinkBuffer.removeFirst()
            let isoFormatter = ISO8601DateFormatter()
            let ts = isoFormatter.string(from: oldest.timestamp)
            appendToFile(url: thinkLogURL, text: "[\(ts)] \(oldest.content)\n")
            checkL2Pruning()
        }
    }
    
    private func checkL2Pruning() {
        guard let data = try? Data(contentsOf: thinkLogURL),
              let text = String(data: data, encoding: .utf8) else { return }
        let lines = text.split(separator: "\n").map(String.init)
        if lines.count > 100 {
            let oldestEntries = lines.prefix(10).joined(separator: "\n")
            let remaining = lines.dropFirst(10).joined(separator: "\n")
            try? remaining.write(to: thinkLogURL, atomically: true, encoding: .utf8)
            let summary = "Summarized Context: \(oldestEntries.prefix(50))..."
            appendToFile(url: publicL2, text: summary + "\n")
        }
        archiveTaskHistoryIfNeeded()
    }
    
    private func archiveTaskHistoryIfNeeded() {
        let paths = PathConfiguration.shared
        let historyURL = paths.applicationSupportURL.appendingPathComponent("task_history.jsonl")
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: historyURL.path),
              let modDate = attrs[.modificationDate] as? Date else { return }
        if Date().timeIntervalSince(modDate) > 30 * 24 * 3600 {
            let archiveURL = paths.applicationSupportURL.appendingPathComponent("task_history_archive.jsonl")
            try? FileManager.default.moveItem(at: historyURL, to: archiveURL)
        }
    }
    
    public func rotateLogsIfNeeded() {
        let logPath = PathConfiguration.shared.auditLogURL
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: logPath.path),
              let size = attrs[.size] as? UInt64 else { return }
        if size > 100 * 1024 * 1024 {
            let isoFormatter = ISO8601DateFormatter()
            let ts = isoFormatter.string(from: Date())
            let archivedURL = PathConfiguration.shared.logsURL.appendingPathComponent("audit.log.\(ts)")
            try? FileManager.default.moveItem(at: logPath, to: archivedURL)
            FileManager.default.createFile(atPath: logPath.path, contents: nil, attributes: nil)
        }
    }
    
    public func getL1() -> [MemoryEntry] {
        return l1Context
    }
    
    /// L2 Retrieval using FileHandle (Item 33 constraints + Item 36 Public/Internal splits)
    public func retrieveL2(query: String, maxBlocks: Int = 3, level: SensitivityLevel = .public) throws -> [String] {
        var matches = [String]()
        
        let pathsToSearch: [URL]
        switch level {
        case .public:
            pathsToSearch = [publicL2]
        case .internal, .confidential:
            pathsToSearch = [publicL2, internalL2]
        }
        
        for p in pathsToSearch {
            guard FileManager.default.fileExists(atPath: p.path) else { continue }
            
            let handle = try FileHandle(forReadingFrom: p)
            defer { try? handle.close() }
            
            let data = try handle.readToEnd() ?? Data()
            guard let text = String(data: data, encoding: .utf8) else { continue }
            
            let lines = text.split(separator: "\n")
            for line in lines {
                if line.localizedCaseInsensitiveContains(query) {
                    matches.append(String(line))
                    if matches.count >= maxBlocks { return matches }
                }
            }
            if matches.count >= maxBlocks { return matches }
        }
        
        return matches
    }
    
    // MARK: - Experiential Memory (RAG)
    
    public func storeExperience(task: String, solution: String) async {
        guard let vector = embedder.getVector(for: task) else { return }
        await vault.save(task: task, solution: solution, embedding: vector)
    }
    
    public func retrieveRelevantExperiences(query: String, limit: Int = 3) async -> String {
        guard let vector = embedder.getVector(for: query) else { return "" }
        let matches = await vault.search(embedding: vector, limit: limit)
        
        if matches.isEmpty { return "" }
        
        var context = "\n### PAST EXPERIENCES (RAG):\n"
        for (task, solution, score) in matches {
            if score > 0.6 { // Semantic Threshold
                context += "- Task: \(task)\n  Solution: \(solution)\n"
            }
        }
        return context
    }
}
