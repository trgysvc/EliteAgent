import Foundation
import Combine
import CryptoKit

/// The central orchestration layer for EliteAgent v9.0 Model Management.
@MainActor
public final class ModelManager: NSObject, ObservableObject {
    public static let shared = ModelManager()
    
    @Published public var downloadProgress: [String: Double] = [:] // modelID -> %
    @Published public var downloadStatus: [String: String] = [:]   // modelID -> "42 MB/s • Kalan: 5 dk"
    @Published public var installedModelIDs: Set<String> = []
    @Published public var vramModelID: String? = nil
    @Published public var loadingModelID: String? = nil
    @Published public var isAutoUnloadEnabled: Bool = true 
    
    private var downloadTasks: [String: URLSessionDownloadTask] = [:]
    private var resumeData: [String: Data] = [:]
    private var retryCounts: [String: Int] = [:]
    private var downloadStartTimes: [String: Date] = [:]
    
    // v21.3: Shard Progress Aggregator
    // baseModelID -> [taskID: (bytesWritten, totalBytes)]
    private var shardProgress: [String: [String: (Int64, Int64)]] = [:]
    
    public let modelsDirectory: URL
    private var session: URLSession!
    
    private let mandatoryFiles = [
        "config.json",
        "tokenizer.json",
        "tokenizer_config.json",
        "special_tokens_map.json"
    ]
    
    private override init() {
        self.modelsDirectory = PathConfiguration.shared.modelsURL
        
        super.init()
        
        let config = URLSessionConfiguration.background(withIdentifier: "com.eliteagent.model-downloader")
        config.sessionSendsLaunchEvents = true
        config.isDiscretionary = false
        
        self.session = URLSession(configuration: config, delegate: self, delegateQueue: nil)
        
        self.refreshInstalledModels()
        self.restoreBackgroundTasks()
    }
    
    // v21.6: Background Task Recovery & Race Prevention
    private func restoreBackgroundTasks() {
        session.getAllTasks { [weak self] tasks in
            guard let self = self else { return }
            
            for task in tasks {
                guard let downloadTask = task as? URLSessionDownloadTask,
                      let taskID = downloadTask.taskDescription else {
                    task.cancel()
                    continue
                }
                
                let baseModelID = taskID.components(separatedBy: "_shard_").first ?? taskID
                
                Task { @MainActor in
                    // If we already have a task for this specific shard, cancel the duplicate to prevent race condition
                    if self.downloadTasks[taskID] != nil {
                        AgentLogger.logAudit(level: .warn, agent: "ModelManager", message: "Killed duplicate ghost task for: \(taskID)")
                        downloadTask.cancel()
                    } else {
                        self.downloadTasks[taskID] = downloadTask
                        if self.downloadStartTimes[baseModelID] == nil {
                            self.downloadStartTimes[baseModelID] = Date()
                        }
                        
                        if self.downloadProgress[baseModelID] == nil {
                            self.downloadProgress[baseModelID] = 0.01
                            self.downloadStatus[baseModelID] = "Bağlantı sürdürülüyor..."
                        }
                    }
                }
            }
        }
    }
    
    // MARK: - API
    
    /// Automated setup for the local provider during onboarding.
    public func setupLocalProvider() async throws {
        let recommendation = AutoConfigManager.shared.recommendation
        
        let tier = recommendation.recommendedTier
        let modelID: String
        
        switch tier {
        case .high: modelID = "qwen-3.5-7b-4bit"
        case .balanced: modelID = "qwen-2.5-7b-4bit"
        case .low: modelID = "qwen-2.5-3b-4bit"
        }
        
        AgentLogger.logAudit(level: .info, agent: "ModelManager", message: "Auto-Setup: Detected \(recommendation.ramDescription), recommending \(modelID) for tier \(tier)")
        
        guard let model = ModelRegistry.availableModels.first(where: { $0.id == modelID }) else {
            throw ModelError.unknown("Önerilen model catálogo'da bulunamadı: \(modelID)")
        }
        
        try await download(model)
        
        // Note: Auto-load on finish is handled via URLSession delegate when download finishes
    }
    
    public func refreshInstalledModels() {
        guard let contents = try? FileManager.default.contentsOfDirectory(at: modelsDirectory, includingPropertiesForKeys: nil) else { return }
        
        var found: Set<String> = []
        for url in contents where url.hasDirectoryPath {
            let modelID = url.lastPathComponent
            
            // v10.7: Centralized Integrity Check
            if verifyIntegrity(id: modelID) {
                found.insert(modelID)
            }
        }
        self.installedModelIDs = found
    }
    
    public func download(_ model: ModelCatalog) async throws {
        guard !model.downloadURL.isEmpty else { return }
        guard downloadTasks[model.id] == nil else { return }
        
        // v21.5: Prevent redundant ghost downloads if files are already fully intact
        if verifyIntegrity(id: model.id) {
            AgentLogger.logAudit(level: .info, agent: "ModelManager", message: "Download requested for \(model.name), but integrity check passed. Skipping redundant download.")
            
            await MainActor.run {
                self.downloadProgress[model.id] = 1.0
                self.downloadStatus[model.id] = "Yüklendi (Hazır)"
                self.refreshInstalledModels()
            }
            return
        }
        
        AgentLogger.logAudit(level: .info, agent: "ModelManager", message: "Starting download: \(model.name)")
        
        // 1. Fetch metadata first (Only SMALL configuration files)
        try await downloadModelMetadata(model)
        
        // 2. Prepare download queue
        var urlsToDownload: [URL] = []
        if let mainURL = URL(string: model.downloadURL) {
            urlsToDownload.append(mainURL)
            
            // v21.0: Proper Shard Discovery for multi-file models
            if model.id.contains("3.5") || model.id.contains("9b") {
                let base = mainURL.deletingLastPathComponent()
                // If it's a shard, detect sibling shards
                if mainURL.lastPathComponent.contains("-00001-of-") {
                    let shard2 = base.appendingPathComponent("model-00002-of-00002.safetensors")
                    urlsToDownload.append(shard2)
                }
            }
        }
        
        // 3. Kick off background tasks
        for (index, url) in urlsToDownload.enumerated() {
            let taskID = index == 0 ? model.id : "\(model.id)_shard_\(index)"
            let task = session.downloadTask(with: url)
            task.taskDescription = taskID
            
            if index == 0 {
                downloadTasks[model.id] = task
                downloadStartTimes[model.id] = Date()
            } else {
                // Secondary shards don't update the primary UI progress but must be tracked
                downloadTasks[taskID] = task
            }
            
            task.resume()
        }
        
        updateProgress(for: model.id, progress: 0.01)
    }
    
    /// User-facing repair trigger.
    public func repairModel(_ modelID: String) async throws {
        guard let catalog = ModelRegistry.availableModels.first(where: { $0.id == modelID }) else { return }
        
        // 1. Refresh basic metadata (small files)
        try await downloadModelMetadata(catalog)
        
        // 2. If it's still not complete, trigger full download for weights
        if !verifyIntegrity(id: modelID) {
            AgentLogger.logAudit(level: .info, agent: "ModelManager", message: "Integrity check failed after metadata repair for \(modelID). Triggering weight download...")
            try await self.download(catalog)
        } else {
            refreshInstalledModels()
        }
    }
    
    /// Strict verification of all mandatory files.
    public func verifyModelComplete(_ modelID: String) throws {
        if !verifyIntegrity(id: modelID) {
            throw ModelError.incompleteDownload(missing: "Kritik dosyalar veya parçalar (shards) eksik.")
        }
    }
    
    /// v10.7: Single Source of Truth for Model Integrity
    public func verifyIntegrity(id modelID: String) -> Bool {
        let modelURL = modelsDirectory.appendingPathComponent(modelID)
        
        let mandatory = ["config.json", "tokenizer.json"]
        for file in mandatory {
            if !FileManager.default.fileExists(atPath: modelURL.appendingPathComponent(file).path) { return false }
        }
        
        // Weight Detection (Support Shards)
        let weightsExist = FileManager.default.fileExists(atPath: modelURL.appendingPathComponent("model.safetensors").path) ||
                           FileManager.default.fileExists(atPath: modelURL.appendingPathComponent("weights.npz").path)
        
        if weightsExist { return true }
        
        // Multi-shard check for 9B/3.5 models
        if modelID.contains("3.5") || modelID.contains("9b") {
            let shard1 = FileManager.default.fileExists(atPath: modelURL.appendingPathComponent("model-00001-of-00002.safetensors").path)
            let shard2 = FileManager.default.fileExists(atPath: modelURL.appendingPathComponent("model-00002-of-00002.safetensors").path)
            return shard1 && shard2 // MUST HAVE BOTH
        }
        
        return false
    }
    
    /// Safety check for UI to verify model presence without throwing.
    public func isModelComplete(id: String) -> Bool {
        return verifyIntegrity(id: id)
    }
    
    /// Utility for Resilient Self-Healing to distinguish between "Not Installed" and "Corrupted"
    public func doesModelDirectoryExist(id: String) -> Bool {
        let modelURL = modelsDirectory.appendingPathComponent(id)
        return FileManager.default.fileExists(atPath: modelURL.path)
    }
    
    /// v10.8: Architecture Aliasing & Configuration Hoisting Fix
    /// Some models (like sushi-coder or unsloth exports) use non-standard architecture names 
    /// or hide critical fields (hidden_size) inside a 'text_config' block.
    /// This method maps them to MLX-supported base architectures and hoists missing fields.
    public func patchConfigForArchitectureAliasing(id: String) {
        let configURL = modelsDirectory.appendingPathComponent(id).appendingPathComponent("config.json")
        guard FileManager.default.fileExists(atPath: configURL.path),
              let content = try? String(contentsOf: configURL, encoding: .utf8) else {
            return
        }
        
        var modifiedContent = content
        
        // 1. Architecture Aliasing
        let mappings = [
            "\"model_type\": \"qwen3_5\"": "\"model_type\": \"qwen2\"",
            "\"model_type\": \"qwen3_5_text\"": "\"model_type\": \"qwen2\"",
            "\"architectures\": [\n        \"Qwen3_5ForConditionalGeneration\"\n    ]": "\"architectures\": [\n        \"Qwen2ForCausalLM\"\n    ]"
        ]
        
        var changed = false
        for (pattern, replacement) in mappings {
            if modifiedContent.contains(pattern) {
                modifiedContent = modifiedContent.replacingOccurrences(of: pattern, with: replacement)
                changed = true
            }
        }
        
        // 1.5. Unsloth `lm_head` stripping bug workaround:
        // Unsloth often strips lm_head.weight to save space during 4-bit export but forgets to set tie_word_embeddings to true.
        if modifiedContent.contains("\"unsloth_version\"") {
            if modifiedContent.contains("\"tie_word_embeddings\": false") {
                modifiedContent = modifiedContent.replacingOccurrences(of: "\"tie_word_embeddings\": false", with: "\"tie_word_embeddings\": true")
                changed = true
                AgentLogger.logAudit(level: .info, agent: "ModelManager", message: "PATCH: Fixed Unsloth tie_word_embeddings bug for \(id)")
            }
        }
        
        // 2. Configuration Hoisting (v11.0: Fix for "Missing field 'hidden_size'")
        // If hidden_size is not at the root but is inside text_config, hoist it.
        let criticalFields = ["hidden_size", "intermediate_size", "num_hidden_layers", "num_attention_heads", "num_key_value_heads", "vocab_size", "rms_norm_eps", "max_position_embeddings"]
        
        for field in criticalFields {
            // v11.2: Precise Root Detection. 
            // We search for the field indented exactly at the root level (4 spaces) or right after an opening brace.
            let rootPattern1 = "\n    \"\(field)\":"
            let rootPattern2 = "{\n    \"\(field)\":"
            let textConfigPattern = "\"text_config\": {"
            
            // If it's NOT at the root but text_config exists
            if !modifiedContent.contains(rootPattern1) && !modifiedContent.contains(rootPattern2) && modifiedContent.contains(textConfigPattern) {
                // v11.3: Robust Search supporting floats/exponents (e.g. 1e-06)
                let pattern = "\"text_config\":\\s*\\{(?:[^{}]|\\{[^{}]*\\})*\"\(field)\":\\s*([^,}]+)"
                if let regex = try? NSRegularExpression(pattern: pattern, options: [.dotMatchesLineSeparators]),
                   let match = regex.firstMatch(in: modifiedContent, options: [], range: NSRange(modifiedContent.startIndex..<modifiedContent.endIndex, in: modifiedContent)),
                   let range = Range(match.range(at: 1), in: modifiedContent) {
                    let value = modifiedContent[range]
                    // Insert at the beginning of the JSON object (after the first {)
                    if let firstBrace = modifiedContent.firstIndex(of: "{") {
                        let insertIndex = modifiedContent.index(after: firstBrace)
                        modifiedContent.insert(contentsOf: "\n    \"\(field)\": \(value),", at: insertIndex)
                        changed = true
                        AgentLogger.logAudit(level: .info, agent: "ModelManager", message: "HOIST: Moved \(field) (\(value)) to root for \(id)")
                    }
                }
            }
        }
        
        if changed {
            try? modifiedContent.write(to: configURL, atomically: true, encoding: .utf8)
            AgentLogger.logAudit(level: .info, agent: "ModelManager", message: "PATCH: Configuration normalized for \(id)")
        }
    }
    
    private func downloadModelMetadata(_ model: ModelCatalog) async throws {
        let baseRepoURL = URL(string: model.downloadURL)!.deletingLastPathComponent()
        let destinationDir = modelsDirectory.appendingPathComponent(model.id)
        try? FileManager.default.createDirectory(at: destinationDir, withIntermediateDirectories: true)
        
        let filesToDownload = mandatoryFiles // v21.0: Strictly metadata only. No shards here.
        
        for fileName in filesToDownload {
            let fileURL = baseRepoURL.appendingPathComponent(fileName)
            let destFile = destinationDir.appendingPathComponent(fileName)
            
            if !FileManager.default.fileExists(atPath: destFile.path) {
                AgentLogger.logAudit(level: .info, agent: "ModelManager", message: "Fetching metadata: \(fileName)")
                do {
                    let (data, _) = try await URLSession.shared.data(from: fileURL)
                    try data.write(to: destFile)
                } catch {
                    AgentLogger.logAudit(level: .warn, agent: "ModelManager", message: "Failed to fetch metadata: \(fileName)")
                }
            }
        }
    }
    
    public func resolveModelPath(_ modelID: String) -> URL {
        let canonical = modelsDirectory.appendingPathComponent(modelID)
        if FileManager.default.fileExists(atPath: canonical.path) {
            return canonical
        }
        
        // v9.9.1: Fallback to case-insensitive and legacy names
        let legacyNames = [
            modelID.lowercased()
        ]
        
        for legacyName in legacyNames {
            let path = modelsDirectory.appendingPathComponent(legacyName)
            if FileManager.default.fileExists(atPath: path.path) {
                return path
            }
        }
        
        return canonical // Return canonical even if missing to allow verifyModelComplete to catch it properly
    }

    public func load(_ modelID: String) async throws {
        let modelURL = resolveModelPath(modelID)
        
        // 1. Verify completeness first
        do {
            try verifyModelComplete(modelID)
        } catch ModelError.incompleteDownload {
            // Attempt auto-repair once
            if let catalog = ModelRegistry.availableModels.first(where: { $0.id == modelID }) {
                try await downloadModelMetadata(catalog)
            }
            try verifyModelComplete(modelID) // Re-verify
        }
        
        try await InferenceActor.shared.loadModel(at: modelURL)
        self.vramModelID = modelID
        
        // v9.9.6: Notify observers that models have changed (Sync fix)
        NotificationCenter.default.post(name: .modelsDidChange, object: nil)
    }
    
    public func switchTo(_ modelID: String) async throws {
        do {
            self.loadingModelID = modelID
            // v11.1: Use restart() for a complete hard reset before loading the new model
            if isAutoUnloadEnabled { 
                AgentLogger.logAudit(level: .warn, agent: "ModelManager", message: "Hard Resetting engine before switching to \(modelID)")
                await InferenceActor.shared.restart() 
            }
            try await load(modelID)
            self.loadingModelID = nil
            NotificationCenter.default.post(name: .activeProviderChanged, object: modelID)
        } catch {
            self.loadingModelID = nil
            throw error
        }
    }
    
    public func unload(_ modelID: String) async {
        await InferenceActor.shared.restart()
        if self.vramModelID == modelID {
            self.vramModelID = nil
        }
    }
    
    private func unloadActiveLocalModel() async {
        await InferenceActor.shared.restart()
        self.vramModelID = nil
    }
    
    private func updateProgress(for modelID: String, progress: Double) {
        self.downloadProgress[modelID] = progress
    }
}

// v9.9.6: Notification Sync
extension Notification.Name {
    static let modelsDidChange = Notification.Name("modelsDidChange")
}

// MARK: - URLSessionDownloadDelegate
extension ModelManager: URLSessionDownloadDelegate {
    
    nonisolated public func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didWriteData bytesWritten: Int64, totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64) {
        guard let taskID = downloadTask.taskDescription else { return }
        let baseModelID = taskID.components(separatedBy: "_shard_").first ?? taskID
        
        Task { [weak self] in
            guard let self = self else { return }
            
            // 1. Update shard-specific progress
            await MainActor.run {
                var current = self.shardProgress[baseModelID] ?? [:]
                current[taskID] = (totalBytesWritten, totalBytesExpectedToWrite)
                self.shardProgress[baseModelID] = current
            }
            
            // 2. Aggregate data for unified reporting
            let stats = await MainActor.run { self.shardProgress[baseModelID] ?? [:] }
            var combinedWritten: Int64 = 0
            var combinedTotal: Int64 = 0
            
            for (_, progress) in stats {
                combinedWritten += progress.0
                combinedTotal += progress.1
            }
            
            guard combinedTotal > 0 else { return }
            
            // 3. Calculate Speed and Time based on aggregate
            let startTime = await self.downloadStartTimes[baseModelID]
            if let startTime = startTime {
                let elapsed = Date().timeIntervalSince(startTime)
                if elapsed > 0 {
                    // v21.4: Unified Reporting with Fallback Sizes
                    let catalogSizeInBytes: Int64 = {
                        if baseModelID.contains("3.5") || baseModelID.contains("9b") { return 5_476_083_302 } // 5.1 GB approx
                        return 4_509_715_660 // 4.2 GB approx
                    }()
                    
                    let effectiveTotal = combinedTotal > 0 ? combinedTotal : catalogSizeInBytes
                    let overallProgress = Double(combinedWritten) / Double(effectiveTotal)
                    
                    let startTime = await self.downloadStartTimes[baseModelID]
                    if let startTime = startTime {
                        let elapsed = Date().timeIntervalSince(startTime)
                        if elapsed > 0 {
                            let bytesPerSecond = Double(combinedWritten) / elapsed
                            let speedMBs = bytesPerSecond / 1_048_576.0
                            
                            let remainingBytes = Double(effectiveTotal - combinedWritten)
                            let remainingSeconds = remainingBytes / bytesPerSecond
                            let remainingMins = Int(remainingSeconds / 60)
                            
                            let writtenGB = Double(combinedWritten) / 1_073_741_824.0
                            let totalGB = Double(effectiveTotal) / 1_073_741_824.0
                            
                            let status: String
                            if speedMBs < 0.1 {
                                status = "Bağlantı kuruluyor..."
                            } else {
                                status = String(format: "%.1f MB/s • %.1f/%.1f GB • Kalan: %d dk", 
                                              speedMBs, writtenGB, totalGB, remainingMins)
                            }
                            
                            await MainActor.run {
                                self.downloadProgress[baseModelID] = min(0.99, overallProgress)
                                self.downloadStatus[baseModelID] = status
                            }
                        }
                    }
                }
            }
        }
    }
    
    nonisolated public func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
        guard let taskID = downloadTask.taskDescription else { return }
        
        // v21.2: Resolve base model ID from shard task ID
        let baseModelID = taskID.components(separatedBy: "_shard_").first ?? taskID
        
        let modelsDir = self.modelsDirectory
        let destinationURL = modelsDir.appendingPathComponent(baseModelID)
        try? FileManager.default.createDirectory(at: destinationURL, withIntermediateDirectories: true)
        
        let originalFileName = downloadTask.originalRequest?.url?.lastPathComponent ?? "model.bin"
        let finalPath = destinationURL.appendingPathComponent(originalFileName)
        
        do {
            if FileManager.default.fileExists(atPath: finalPath.path) {
                try FileManager.default.removeItem(at: finalPath)
            }
            try FileManager.default.moveItem(at: location, to: finalPath)
            
            Task { @MainActor [weak self] in
                guard let self = self else { return }
                self.downloadTasks.removeValue(forKey: taskID)
                
                // Aggregated Completion Check
                let relatedTasks = self.downloadTasks.keys.filter { $0 == baseModelID || $0.hasPrefix("\(baseModelID)_shard_") }
                
                if relatedTasks.isEmpty {
                    self.downloadProgress[baseModelID] = 1.0
                    self.downloadStatus[baseModelID] = "Yüklendi (Hazır)"
                    self.refreshInstalledModels()
                } else {
                    self.downloadStatus[baseModelID] = "Parçalar birleştiriliyor (\(relatedTasks.count) parça kaldı)..."
                }
            }
        } catch {
            print("[ModelManager] CRITICAL: Failed to save model file: \(error)")
        }
    }
    
    nonisolated public func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        guard let modelID = task.taskDescription else { return }
        
        if let error = error {
            Task { [weak self] in
                guard let self = self else { return }
                
                if let resumeData = (error as NSError).userInfo[NSURLSessionDownloadTaskResumeData] as? Data {
                    await MainActor.run { self.resumeData[modelID] = resumeData }
                }
                
                let retryCount = await self.retryCounts[modelID] ?? 0
                if retryCount < 3 {
                    await MainActor.run {
                        self.retryCounts[modelID] = retryCount + 1
                        self.downloadStatus[modelID] = "Yeniden deneniyor (\(retryCount + 1)/3)..."
                    }
                    
                    try? await Task.sleep(nanoseconds: 2 * 1_000_000_000)
                    if let catalog = ModelRegistry.availableModels.first(where: { $0.id == modelID }) {
                        try? await self.download(catalog)
                    }
                } else {
                    await MainActor.run {
                        self.downloadStatus[modelID] = "Hata"
                        self.downloadTasks.removeValue(forKey: modelID)
                    }
                }
            }
        }
    }
}
