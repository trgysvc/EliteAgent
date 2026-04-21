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
        if downloadTasks[model.id] != nil { return } 
        
        AgentLogger.logAudit(level: .info, agent: "ModelManager", message: "Starting download: \(model.name)")
        
        // 1. Fetch metadata first (small files, done immediately)
        try await downloadModelMetadata(model)
        
        // 2. Start main weight download
        let url = URL(string: model.downloadURL)!
        let task: URLSessionDownloadTask
        
        if let data = resumeData[model.id] {
            task = session.downloadTask(withResumeData: data)
            resumeData.removeValue(forKey: model.id)
        } else {
            task = session.downloadTask(with: url)
        }
        
        task.taskDescription = model.id
        downloadTasks[model.id] = task
        downloadStartTimes[model.id] = Date()
        task.resume()
        
        updateProgress(for: model.id, progress: 0.01)
    }
    
    /// User-facing repair trigger.
    public func repairModel(_ modelID: String) async throws {
        guard let catalog = ModelRegistry.availableModels.first(where: { $0.id == modelID }) else { return }
        try await downloadModelMetadata(catalog)
        refreshInstalledModels()
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
        
        // 2. Configuration Hoisting (v11.0: Fix for "Missing field 'hidden_size'")
        // If hidden_size is not at the root but is inside text_config, hoist it.
        let criticalFields = ["hidden_size", "intermediate_size", "num_hidden_layers", "num_attention_heads", "num_key_value_heads", "vocab_size"]
        
        for field in criticalFields {
            let rootPattern = "\"\(field)\":"
            let textConfigPattern = "\"text_config\": {"
            
            // If it's NOT at the root but text_config exists
            if !modifiedContent.contains(rootPattern) && modifiedContent.contains(textConfigPattern) {
                // Find the value inside text_config using regex
                let pattern = "\"text_config\":\\s*\\{[^}]*\"\(field)\":\\s*(\\d+)"
                if let regex = try? NSRegularExpression(pattern: pattern, options: []),
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
        
        var filesToDownload = mandatoryFiles
        
        // v10.0: Automatic Shard Detection for large models
        if model.id.contains("3.5") || model.id.contains("9b") {
            filesToDownload.append("model-00001-of-00002.safetensors")
            filesToDownload.append("model-00002-of-00002.safetensors")
        }
        
        for fileName in filesToDownload {
            let fileURL = baseRepoURL.appendingPathComponent(fileName)
            let destFile = destinationDir.appendingPathComponent(fileName)
            
            if !FileManager.default.fileExists(atPath: destFile.path) {
                AgentLogger.logAudit(level: .info, agent: "ModelManager", message: "Fetching file: \(fileName)")
                do {
                    let (data, _) = try await URLSession.shared.data(from: fileURL)
                    try data.write(to: destFile)
                } catch {
                    AgentLogger.logAudit(level: .warn, agent: "ModelManager", message: "Failed to fetch: \(fileName)")
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
        guard let modelID = downloadTask.taskDescription else { return }
        
        let progress = Double(totalBytesWritten) / Double(totalBytesExpectedToWrite)
        
        Task { [weak self] in
            guard let self = self else { return }
            let startTime = await self.downloadStartTimes[modelID]
            
            if let startTime = startTime {
                let elapsed = Date().timeIntervalSince(startTime)
                if elapsed > 0 {
                    let bytesPerSecond = Double(totalBytesWritten) / elapsed
                    let speedMBs = bytesPerSecond / 1_048_576.0 // MB/s
                    
                    let remainingBytes = Double(totalBytesExpectedToWrite - totalBytesWritten)
                    let remainingSeconds = remainingBytes / bytesPerSecond
                    let remainingMins = Int(remainingSeconds / 60)
                    
                    let status = String(format: "%.1f MB/s • Kalan: %d dk", speedMBs, remainingMins)
                    
                    await MainActor.run {
                        self.downloadProgress[modelID] = progress
                        self.downloadStatus[modelID] = status
                    }
                }
            }
        }
    }
    
    nonisolated public func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
        guard let modelID = downloadTask.taskDescription else { return }
        
        let modelsDir = self.modelsDirectory
        let destinationURL = modelsDir.appendingPathComponent(modelID)
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
                self.downloadTasks.removeValue(forKey: modelID)
                self.downloadProgress[modelID] = 1.0
                self.downloadStatus[modelID] = "Yüklendi (Hazır)"
                self.refreshInstalledModels()
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
