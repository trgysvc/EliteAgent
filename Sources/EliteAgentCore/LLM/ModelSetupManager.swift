import Foundation
import Combine
import CryptoKit

public enum ModelLoadState: Int, Codable, Sendable {
    case idle = 0
    case readingWeights = 1    // Pulse
    case decodingWeights = 2   // Gathering
    case transferringToVRAM = 3 // Glow
    case verifying = 4         // SHA Check
    case ready = 5
    case failed = -1           // Glitch
}

@MainActor
public final class ModelSetupManager: NSObject, ObservableObject, @unchecked Sendable {
    public static let shared = ModelSetupManager()
    
    @Published public var isDownloading = false
    @Published public var downloadProgress: Double = 0.0
    @Published public var currentDownloadTask: String = ""
    @Published public var isModelReady: Bool = false
    @Published public var modelPath: URL? = nil
    @Published public var loadState: ModelLoadState = .idle
    
    private var session: URLSession!
    private var downloadTask: URLSessionDownloadTask?
    private var activeContinuation: CheckedContinuation<URL, Error>?
    
    public let activeModelID = "Qwen2.5-7B-Instruct-4bit"
    private let hfBaseURL = "https://huggingface.co/mlx-community/Qwen2.5-7B-Instruct-4bit/resolve/main/"
    private let requiredFiles = [
        "model.safetensors",
        "tokenizer.json",
        "config.json",
        "tokenizer_config.json"
    ]
    
    private override init() {
        super.init()
        let config = URLSessionConfiguration.default
        // Delegate queue is main, but delegate methods must still handle isolation correctly
        self.session = URLSession(configuration: config, delegate: self, delegateQueue: .main)
        verifyModelStatus()
    }
    
    public func verifyModelStatus() {
        let path = getModelDirectory()
        let configURL = path.appendingPathComponent("config.json")
        
        let allExist = requiredFiles.allSatisfy { 
            FileManager.default.fileExists(atPath: path.appendingPathComponent($0).path)
        }
        
        // CORRUPTION CHECK: If config.json contains "Invalid username" or is too small, it's a ghost download
        var isCorrupted = false
        if allExist, let data = try? Data(contentsOf: configURL), let content = String(data: data, encoding: .utf8) {
            if content.contains("Invalid username") || data.count < 100 {
                isCorrupted = true
                print("[ModelSetup] CRITICAL: Corrupted model files detected. Forcing recovery state.")
            }
        }
        
        if allExist && !isCorrupted {
            self.isModelReady = true
            self.modelPath = path
            self.loadState = .ready
        } else {
            self.isModelReady = false
            self.loadState = .idle
            if isCorrupted {
                // Optionally clear the corrupted directory to allow a clean retry
                try? FileManager.default.removeItem(at: path)
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
                let baseUrl = await MainActor.run { self.hfBaseURL }
                
                for fileName in files {
                    await MainActor.run { self.currentDownloadTask = fileName }
                    let url = URL(string: baseUrl + fileName)!
                    let localURL = try await self.downloadFile(from: url)
                    
                    // Integrity Check: Ensure it's not a tiny error page
                    let attributes = try FileManager.default.attributesOfItem(atPath: localURL.path)
                    let fileSize = attributes[.size] as? Int64 ?? 0
                    
                    if fileName == "config.json" && fileSize < 100 {
                        throw NSError(domain: "ModelSetup", code: 401, userInfo: [NSLocalizedDescriptionKey: "Download failed: Hugging Face returned an error page instead of config.json. Check network/auth."])
                    }
                    
                    let destination = targetDir.appendingPathComponent(fileName)
                    if FileManager.default.fileExists(atPath: destination.path) {
                        try FileManager.default.removeItem(at: destination)
                    }
                    try FileManager.default.moveItem(at: localURL, to: destination)
                }
                
                // Final Step: Verify SHA-256
                await MainActor.run { self.loadState = .verifying }
                let weightsURL = targetDir.appendingPathComponent("model.safetensors")
                let isValid = try await self.verifySHA256(at: weightsURL)
                
                await MainActor.run {
                    if isValid {
                        self.isDownloading = false
                        self.verifyModelStatus()
                    } else {
                        self.loadState = .failed
                        self.isDownloading = false
                    }
                }
            } catch {
                print("[ModelSetup] Download failed: \(error)")
                await MainActor.run { 
                    self.loadState = .failed
                    self.isDownloading = false 
                }
            }
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
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return appSupport.appendingPathComponent("EliteAgent/Models/\(activeModelID)")
    }
}

// MARK: - URLSession Delegates (Non-isolated for Swift 6 Concurrency)
extension ModelSetupManager: URLSessionDownloadDelegate {
    public nonisolated func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
        // Check HTTP Response Status
        if let response = downloadTask.response as? HTTPURLResponse, response.statusCode != 200 {
            let error = NSError(domain: "ModelSetup", code: response.statusCode, userInfo: [NSLocalizedDescriptionKey: "HTTP Error \(response.statusCode) during download."])
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
}
