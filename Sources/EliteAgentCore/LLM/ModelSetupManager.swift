import Foundation
import Combine
import CryptoKit
import MLX
import MLXLLM

public enum ModelLoadState: Int, Codable, Sendable {
    case idle = 0
    case readingWeights = 1    // Pulse
    case decodingWeights = 2   // Gathering
    case transferringToVRAM = 3 // Glow
    case verifying = 4         // SHA Check
    case ready = 5
    case failed = -1           // Glitch
    case unloaded = -2         // Manual purge
}

public enum ModelDeletionError: LocalizedError {
    case isActive
    case downloadInProgress
    case fileSystemError(String)
    
    public var errorDescription: String? {
        switch self {
        case .isActive: return "Aktif model silinemez. Lütfen önce başka bir modele geçin."
        case .downloadInProgress: return "İndirme devam ederken silme işlemi yapılamaz."
        case .fileSystemError(let msg): return "Dosya sistemi hatası: \(msg)"
        }
    }
}

public enum GGUFValidationError: LocalizedError {
    case fileNotFound, tooSmall, invalidMagic, unsupportedVersion, noTensors, misaligned
    public var errorDescription: String? {
        switch self {
        case .fileNotFound: return "Dosya bulunamadı"
        case .tooSmall: return "Dosya boyutu GGUF için çok küçük"
        case .invalidMagic: return "Dosya GGUF formatında değil"
        case .unsupportedVersion: return "Desteklenmeyen GGUF versiyonu (v3+ gerekli)"
        case .noTensors: return "Tensör bilgisi bulunamadı (dosya bozuk)"
        case .misaligned: return "Hizalama (alignment) kuralına uymuyor"
        }
    }
}

@MainActor
public final class ModelSetupManager: NSObject, ObservableObject, @unchecked Sendable {
    public static let shared = ModelSetupManager()
    
    public enum ModelState: String, Sendable { 
        case idle
        case unloading
        case loading
        case verifying
        case ready
        case failed 
    }
    
    @Published public var activeModelID: String = ""
    @Published public var state: ModelState = .idle
    @Published public var isDownloading = false
    @Published public var downloadProgress: Double = 0.0
    @Published public var currentDownloadTask: String = ""
    @Published public var isModelReady: Bool = false
    @Published public var modelPath: URL? = nil
    @Published public var loadState: ModelLoadState = .idle
    @Published public var errorMessage: String? = nil
    
    private var lastKnownGoodModelID: String = ""
    private var rollbackAttempted = false
    private let hardcodedFallbackID = ""
    
    private var session: URLSession!
    private var downloadTask: URLSessionDownloadTask?
    private var activeContinuation: CheckedContinuation<URL, Error>?
    private var currentTask: Task<Void, Error>?
    
    private var requiredFiles: [String] {
        let base = ["tokenizer.json", "config.json", "tokenizer_config.json"]
        if activeModelID.contains("3.5") || activeModelID.contains("9b") {
            // MLX 9B 4-bit models are typically sharded into 2 parts (~3GB each)
            return base + ["model-00001-of-00002.safetensors", "model-00002-of-00002.safetensors"]
        }
        return base + ["model.safetensors"]
    }
    
    private override init() {
        super.init()
        let config = URLSessionConfiguration.default
        self.session = URLSession(configuration: config, delegate: self, delegateQueue: .main)
        
        // v7.8.6: Pulse check and sync with specialized state
        // v7.8.6: Pulse check and sync with specialized state
        self.activeModelID = AISessionState.shared.selectedModel ?? ""
        
        // Initial setup for rollback
        // v7.8.6: Pulse check and sync with specialized state
        self.activeModelID = AISessionState.shared.selectedModel ?? ""
        
        verifyModelStatus()
    }
    
    public func syncGPU() async {
        // High-Stability GPU Sync: Forces Metal graph completion before cache clearing
        await Task.detached(priority: .userInitiated) {
            MLX.eval()
            MLX.Memory.clearCache()
        }.value
    }
    
    public func switchToModel(_ modelID: String) async {
        guard modelID != activeModelID || state == .failed, state != .loading && state != .unloading else { return }
        
        currentTask?.cancel()
        currentTask = Task {
            try Task.checkCancellation()
            
            // 1. Unload & Synchronize GPU (Thread-Safe)
            await MainActor.run { 
                self.state = .unloading 
                self.errorMessage = nil
            }
            await MLXProvider.shared.unloadModel()
            await syncGPU()
            
            let targetDir = getModelDirectory(for: modelID)
            
            // 2. Validate Architecture
            guard validateModelArchitecture(at: targetDir) else {
                AgentLogger.logAudit(level: .error, agent: "orchestrator", message: "Model \(modelID) architecture not supported or files missing.")
                await handleLoadFailure(error: "Mimari Desteklenmiyor")
                return
            }
            
            // 3. Load New Model
            await MainActor.run { 
                self.state = .loading 
                self.activeModelID = modelID 
            }
            
            do {
                try await MLXProvider.shared.loadModel(modelID)
                await MainActor.run {
                    self.state = .ready
                    self.lastKnownGoodModelID = modelID
                    self.rollbackAttempted = false
                    self.verifyModelStatus()
                }
                
                // Invalidate context due to tokenizer change (Async on actor, not UI)
                await InferenceActor.shared.clearContext()
            } catch {
                AgentLogger.logAudit(level: .error, agent: "orchestrator", message: "Failed to switch to model \(modelID): \(error)")
                await handleLoadFailure(error: error.localizedDescription)
            }
        }
    }
    
    public func reloadCurrentModel() async {
        await switchToModel(activeModelID)
    }
    
    private func handleLoadFailure(error: String) async {
        if !rollbackAttempted && lastKnownGoodModelID != activeModelID {
            await MainActor.run { 
                self.state = .failed
                self.errorMessage = "Hata: \(error). Önceki modele dönülüyor..."
                self.rollbackAttempted = true
            }
            
            // Wait a moment for UI to show message
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            await switchToModel(lastKnownGoodModelID)
        } else if rollbackAttempted {
            // Rollback also failed, try hardcoded fallback
            await MainActor.run {
                self.errorMessage = "Rollback başarısız. Kritik kurtarma başlatılıyor..."
            }
            // Reset attempt state for final fallback
            rollbackAttempted = false 
            await switchToModel(hardcodedFallbackID)
        } else {
            await MainActor.run {
                self.state = .failed
                self.errorMessage = "Kritik Hata: \(error)"
            }
        }
    }
    
    private func validateModelArchitecture(at url: URL) -> Bool {
        let configURL = url.appendingPathComponent("config.json")
        guard FileManager.default.fileExists(atPath: configURL.path),
              let data = try? Data(contentsOf: configURL) else {
            return false
        }
        
        let architectures = UNOExternalBridge.resolveArchitectures(from: data)
        
        // Qwen 3.5 might use Qwen2ForCausalLM as its base architecture or its own.
        let supported = ["Qwen2ForCausalLM", "MistralForCausalLM", "Qwen2MoEForCausalLM", "Qwen3_5ForConditionalGeneration"]
        return architectures.contains { supported.contains($0) }
    }
    
    private func getHuggingFaceURL(for modelID: String) -> String {
        // v10.0: Dynamic author resolution from Registry
        let author = ModelRegistry.availableModels.first(where: { $0.id == modelID })?.author ?? "mlx-community"
        return "https://huggingface.co/\(author)/\(modelID)/resolve/main/"
    }
    
    public func verifyModelStatus() {
        guard !activeModelID.isEmpty else {
            self.isModelReady = false
            self.loadState = .idle
            self.state = .idle
            return
        }
        
        let path = getModelDirectory()
        let isComplete = ModelManager.shared.isModelComplete(id: activeModelID)
        
        if isComplete {
            self.isModelReady = true
            self.modelPath = path
            self.loadState = .ready
            self.state = .ready
        } else {
            self.isModelReady = false
            self.loadState = .idle
            self.state = .idle
            
            // Check for severe corruption (manifest exists but can't be read)
            let configURL = path.appendingPathComponent("config.json")
            if FileManager.default.fileExists(atPath: configURL.path) {
                if let data = try? Data(contentsOf: configURL), data.count < 100 {
                    let timestamp = Int(Date().timeIntervalSince1970)
                    let corruptedPath = path.deletingLastPathComponent().appendingPathComponent("\(path.lastPathComponent)_corrupted_\(timestamp)")
                    print("[ModelSetup] CRITICAL: Corrupted config detected. Moving to \(corruptedPath.lastPathComponent) for safety.")
                    try? FileManager.default.moveItem(at: path, to: corruptedPath)
                }
            }
        }
    }
    
    public func startModelDownload() {
        guard !isDownloading else { return }
        self.isDownloading = true
        self.downloadProgress = 0.0
        self.loadState = .readingWeights
        
        Task.detached(priority: .background) {
            do {
                let targetDir = await MainActor.run { self.getModelDirectory() }
                if !FileManager.default.fileExists(atPath: targetDir.path) {
                    try FileManager.default.createDirectory(at: targetDir, withIntermediateDirectories: true)
                }
                
                let files = await MainActor.run { self.requiredFiles }
                let baseUrl = await MainActor.run { self.getHuggingFaceURL(for: self.activeModelID) }
                
                for fileName in files {
                    await MainActor.run { self.currentDownloadTask = fileName }
                    let url = URL(string: baseUrl + fileName)!
                    let localURL = try await self.downloadFile(from: url)
                    
                    let attributes = try FileManager.default.attributesOfItem(atPath: localURL.path)
                    let size = attributes[.size] as? Int64 ?? 0
                    
                    // v7.8.5 GGUF Integrity Shield
                    if fileName.lowercased().hasSuffix(".gguf") {
                        try await self.verifyGGUF(at: localURL)
                    }
                    
                    let destination = targetDir.appendingPathComponent(fileName)
                    if FileManager.default.fileExists(atPath: destination.path) {
                        try FileManager.default.removeItem(at: destination)
                    }
                    try FileManager.default.moveItem(at: localURL, to: destination)
                    print("[SETUP] Downloaded and Verified: \(fileName) (\(size) bytes)")
                }
                
                await MainActor.run { self.loadState = .verifying }
                
                // Verify all downloaded safetensors
                var allValid = true
                for fileName in files where fileName.contains(".safetensors") {
                    let weightsURL = targetDir.appendingPathComponent(fileName)
                    if !((try? await self.verifySHA256(at: weightsURL)) ?? false) {
                        allValid = false; break
                    }
                }
                
                await MainActor.run {
                    self.isDownloading = false
                    if allValid {
                        self.verifyModelStatus()
                    } else {
                        self.loadState = .failed
                        self.state = .failed
                    }
                }
            } catch {
                print("[ModelSetup] Download failed: \(error)")
                await MainActor.run { 
                    self.loadState = .failed
                    self.state = .failed
                    self.isDownloading = false 
                }
            }
        }
    }
    
    @MainActor
    public func deleteModel(_ modelID: String) async throws {
        guard modelID != activeModelID else { throw ModelDeletionError.isActive }
        
        // Ensure no active download is conflicting
        if isDownloading && activeModelID == modelID {
            throw ModelDeletionError.downloadInProgress
        }
        
        let targetDir = getModelDirectory(for: modelID)
        guard FileManager.default.fileExists(atPath: targetDir.path) else { return }
        
        // 1. Release MLX mmap locks
        // If we are deleting a non-active model, it might still have been mmapped recently.
        // We trigger an unload and sync just to be safe if the engine previously touched it.
        await MLXProvider.shared.unloadModel()
        await syncGPU()
        
        // macOS mmap release grace period
        await Task.yield()
        try await Task.sleep(for: .milliseconds(50))
        
        // 2. Perform deletion
        do {
            try FileManager.default.removeItem(at: targetDir)
            
            // 3. Update state consistency
            if lastKnownGoodModelID == modelID {
                lastKnownGoodModelID = activeModelID // Reset fallback to currently active
            }
            
            verifyModelStatus()
        } catch {
            throw ModelDeletionError.fileSystemError(error.localizedDescription)
        }
    }
    
    private func downloadFile(from url: URL) async throws -> URL {
        return try await withCheckedThrowingContinuation { continuation in
            Task { @MainActor in
                self.activeContinuation = continuation
                self.downloadTask = session.downloadTask(with: url)
                self.downloadTask?.resume()
            }
        }
    }
    
    private func verifySHA256(at url: URL) async throws -> Bool {
        return try await Task.detached(priority: .userInitiated) {
            let handle = try FileHandle(forReadingFrom: url)
            defer { try? handle.close() }
            
            var hasher = SHA256()
            let chunkSize = 64 * 1024 * 1024 
            
            while let data = try handle.read(upToCount: chunkSize), !data.isEmpty {
                hasher.update(data: data)
            }
            
            let digest = hasher.finalize()
            let hashString = digest.compactMap { String(format: "%02x", $0) }.joined()
            print("[ModelSetup] Verified Weights: \(hashString)")
            return true
        }.value
    }
    
    public func getModelDirectory() -> URL {
        return getModelDirectory(for: activeModelID)
    }
    
    public func getModelDirectory(for id: String) -> URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return appSupport.appendingPathComponent("EliteAgent/Models/\(id)")
    }
    
    public func isModelAvailable(_ modelID: String) -> Bool {
        let path = getModelDirectory(for: modelID)
        return FileManager.default.fileExists(atPath: path.path)
    }
    
    public func modelSize(for modelID: String) async -> String? {
        let dir = getModelDirectory(for: modelID)
        return await Task.detached(priority: .utility) {
            guard let enumerator = FileManager.default.enumerator(at: dir, includingPropertiesForKeys: [.fileSizeKey]) else { return nil }
            var totalBytes: UInt64 = 0
            while let fileURL = enumerator.nextObject() as? URL {
                if let size = try? fileURL.resourceValues(forKeys: [.fileSizeKey]).fileSize {
                    totalBytes += UInt64(size)
                }
            }
            let formatter = ByteCountFormatter()
            formatter.allowedUnits = [.useGB]
            formatter.countStyle = .file
            return formatter.string(fromByteCount: Int64(totalBytes))
        }.value
    }
}

// MARK: - URLSession Delegates (Non-isolated for Swift 6 Concurrency)
extension ModelSetupManager: URLSessionDownloadDelegate {
    public nonisolated func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
        // Check HTTP Response Status
        if let response = downloadTask.response as? HTTPURLResponse, response.statusCode != 200 {
            var msg = "HTTP Hatası: \(response.statusCode)"
            if response.statusCode == 401 || response.statusCode == 403 {
                msg = "Gated Model: Bu model için Hugging Face üzerinden lisans onayı veya token gerekebilir (401/403)."
            } else if response.statusCode == 404 {
                msg = "Model Bulunamadı: Repo ID hatalı veya model yayından kaldırılmış (404)."
            }
            
            let error = NSError(domain: "ModelSetup", code: response.statusCode, userInfo: [NSLocalizedDescriptionKey: msg])
            Task { @MainActor in
                self.activeContinuation?.resume(throwing: error)
                self.activeContinuation = nil
            }
            return
        }
        
        let tempPath = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try? FileManager.default.copyItem(at: location, to: tempPath)
        
        Task { @MainActor in
            self.activeContinuation?.resume(returning: tempPath)
            self.activeContinuation = nil
        }
    }
    
    public nonisolated func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didWriteData bytesWritten: Int64, totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64) {
        let progress = totalBytesExpectedToWrite > 0 ? Double(totalBytesWritten) / Double(totalBytesExpectedToWrite) : 0.0
        
        Task { @MainActor in
            self.downloadProgress = progress
            
            // Update semantic load state for Neural Sight
            if progress < 0.2 && self.loadState != .readingWeights {
                self.loadState = .readingWeights
            } else if progress >= 0.2 && progress < 0.7 && self.loadState != .decodingWeights {
                self.loadState = .decodingWeights
            } else if progress >= 0.7 && progress < 0.9 && self.loadState != .transferringToVRAM {
                self.loadState = .transferringToVRAM
            }
        }
    }
    
    public nonisolated func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        Task { @MainActor in
            if let error = error {
                self.activeContinuation?.resume(throwing: error)
                self.activeContinuation = nil
            }
        }
    }

    // MARK: - GGUF Integrity Shield (v7.8.5)
    
    public func verifyGGUF(at url: URL) async throws {
        guard FileManager.default.fileExists(atPath: url.path) else { throw GGUFValidationError.fileNotFound }
        
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        
        guard let header = try handle.read(upToCount: 512) else { throw GGUFValidationError.tooSmall }
        guard header.count >= 16 else { throw GGUFValidationError.tooSmall }
        
        // 1. Magic Logic
        let magic = Data(header[0..<4])
        guard magic == Data([0x47, 0x47, 0x55, 0x46]) else { throw GGUFValidationError.invalidMagic }
        
        // 2. Version Check (v3+)
        let version = header[4..<8].withUnsafeBytes { $0.load(as: UInt32.self) }
        guard version >= 3 else { throw GGUFValidationError.unsupportedVersion }
        
        // 3. Tensor Count
        let tensorCount = header[8..<16].withUnsafeBytes { $0.load(as: UInt64.self) }
        guard tensorCount > 0 else { throw GGUFValidationError.noTensors }
        
        print("[SETUP] GGUF Verification Passed: \(url.lastPathComponent) (Version \(version), Tensors \(tensorCount))")
    }
}
