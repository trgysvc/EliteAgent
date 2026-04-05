import Foundation
import Combine
import CryptoKit

/// The central orchestration layer for EliteAgent v9.0 Model Management.
@MainActor
public final class ModelManager: NSObject, ObservableObject {
    public static let shared = ModelManager()
    
    @Published public var downloadProgress: [String: Double] = [:] // modelID -> %
    @Published public var downloadStatus: [String: String] = [:]   // modelID -> "42 MB/s • Kalan: 5 dk"
    @Published public var loadedModels: Set<String> = []
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
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        self.modelsDirectory = appSupport.appendingPathComponent("EliteAgent/Models")
        
        try? FileManager.default.createDirectory(at: modelsDirectory, withIntermediateDirectories: true)
        
        super.init()
        
        let config = URLSessionConfiguration.background(withIdentifier: "com.eliteagent.model-downloader")
        config.sessionSendsLaunchEvents = true
        config.isDiscretionary = false
        
        self.session = URLSession(configuration: config, delegate: self, delegateQueue: nil)
        
        self.refreshLoadedModels()
    }
    
    // MARK: - API
    
    /// Automated setup for the local provider during onboarding.
    public func setupLocalProvider() async throws {
        let recommendation = AutoConfigManager.shared.recommendation
        let modelID = recommendation.recommendedLocalModelID
        
        AgentLogger.logAudit(level: .info, agent: "ModelManager", message: "Auto-Setup: Detected \(recommendation.ramDescription), recommending \(modelID)")
        
        guard let model = ModelRegistry.availableModels.first(where: { $0.id == modelID }) else {
            throw ModelError.unknown("Önerilen model katalogda bulunamadı: \(modelID)")
        }
        
        try await download(model)
        
        // Note: Auto-load on finish is handled via URLSession delegate when download finishes
    }
    
    public func refreshLoadedModels() {
        guard let contents = try? FileManager.default.contentsOfDirectory(at: modelsDirectory, includingPropertiesForKeys: nil) else { return }
        
        var found: Set<String> = []
        for url in contents where url.hasDirectoryPath {
            let modelID = url.lastPathComponent
            
            // Strict Validation: Need weights AND config
            let weightsExist = FileManager.default.fileExists(atPath: url.appendingPathComponent("model.safetensors").path) ||
                               FileManager.default.fileExists(atPath: url.appendingPathComponent("weights.npz").path)
            let configExists = FileManager.default.fileExists(atPath: url.appendingPathComponent("config.json").path)
            
            if weightsExist && configExists {
                found.insert(modelID)
            }
        }
        self.loadedModels = found
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
        refreshLoadedModels()
    }
    
    /// Strict verification of all mandatory files.
    public func verifyModelComplete(_ modelID: String) throws {
        let modelURL = modelsDirectory.appendingPathComponent(modelID)
        
        // Check for weights
        let weightsExist = FileManager.default.fileExists(atPath: modelURL.appendingPathComponent("model.safetensors").path) ||
                           FileManager.default.fileExists(atPath: modelURL.appendingPathComponent("weights.npz").path)
        guard weightsExist else {
            throw ModelError.incompleteDownload(missing: "model.safetensors")
        }
        
        // Check for metadata
        for file in mandatoryFiles {
            let path = modelURL.appendingPathComponent(file)
            guard FileManager.default.fileExists(atPath: path.path) else {
                throw ModelError.incompleteDownload(missing: file)
            }
        }
    }
    
    private func downloadModelMetadata(_ model: ModelCatalog) async throws {
        let baseRepoURL = URL(string: model.downloadURL)!.deletingLastPathComponent()
        let destinationDir = modelsDirectory.appendingPathComponent(model.id)
        try? FileManager.default.createDirectory(at: destinationDir, withIntermediateDirectories: true)
        
        for fileName in mandatoryFiles {
            let fileURL = baseRepoURL.appendingPathComponent(fileName)
            let destFile = destinationDir.appendingPathComponent(fileName)
            
            if !FileManager.default.fileExists(atPath: destFile.path) {
                AgentLogger.logAudit(level: .info, agent: "ModelManager", message: "Fetching metadata: \(fileName)")
                do {
                    let (data, _) = try await URLSession.shared.data(from: fileURL)
                    try data.write(to: destFile)
                } catch {
                    AgentLogger.logAudit(level: .warn, agent: "ModelManager", message: "Optional metadata missing: \(fileName)")
                }
            }
        }
    }
    
    public func load(_ modelID: String) async throws {
        let modelURL = modelsDirectory.appendingPathComponent(modelID)
        
        // v9.3 Migration: If canonical lowercase ID folder doesn't exist, check for legacy variants
        if !FileManager.default.fileExists(atPath: modelURL.path) {
            let legacyNames = [
                "Qwen2.5-7B-Instruct-4bit",
                "Qwen-2.5-7B-4bit",
                "qwen2.5-7b-4bit"
            ]
            
            for legacyName in legacyNames {
                let legacyPath = modelsDirectory.appendingPathComponent(legacyName)
                if FileManager.default.fileExists(atPath: legacyPath.path) {
                    do {
                        try FileManager.default.moveItem(at: legacyPath, to: modelURL)
                        AgentLogger.logAudit(level: .info, agent: "ModelManager", message: "✅ v9.3 Migrated legacy model folder: \(legacyName) -> \(modelID)")
                        break
                    } catch {
                        AgentLogger.logAudit(level: .error, agent: "ModelManager", message: "Failed to migrate legacy folder \(legacyName): \(error)")
                    }
                }
            }
        }
        
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
        self.loadedModels.insert(modelID)
    }
    
    public func switchTo(_ modelID: String) async throws {
        do {
            self.loadingModelID = modelID
            if isAutoUnloadEnabled { await unloadActiveLocalModel() }
            try await load(modelID)
            self.loadingModelID = nil
            NotificationCenter.default.post(name: .activeProviderChanged, object: modelID)
        } catch {
            self.loadingModelID = nil
            throw error
        }
    }
    
    public func unload(_ modelID: String) async {
        await InferenceActor.shared.unloadModel()
        self.loadedModels.remove(modelID)
    }
    
    private func unloadActiveLocalModel() async {
        await InferenceActor.shared.unloadModel()
    }
    
    private func updateProgress(for modelID: String, progress: Double) {
        self.downloadProgress[modelID] = progress
    }
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
                self.refreshLoadedModels()
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
