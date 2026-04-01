import Foundation
import Combine

@MainActor
public final class ModelSetupManager: NSObject, ObservableObject {
    public static let shared = ModelSetupManager()
    
    @Published public var isModelReady: Bool = false
    @Published public var modelPath: URL?
    @Published public var checkStatus: String = "Checking models..."
    
    // Download State
    @Published public var isDownloading: Bool = false
    @Published public var downloadProgress: Double = 0.0
    @Published public var currentDownloadTask: String = ""
    
    private let defaultModelID = "mistral-7b-instruct-v0.3-4bit"
    private var timer: Timer?
    private var downloadSession: URLSession!
    private var downloadQueue: [URL] = []
    
    private override init() {
        super.init()
        // Use a non-main delegate queue to avoid blocking UI during download callbacks
        self.downloadSession = URLSession(configuration: .default, delegate: self, delegateQueue: nil)
        checkModelStatus()
        
        timer = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self = self else { return }
                if !self.isDownloading { self.checkModelStatus() }
            }
        }
    }
    
    public func checkModelStatus() {
        let modelsDir = modelsDirectory
        let configFile = modelsDir.appendingPathComponent("config.json")
        
        if !FileManager.default.fileExists(atPath: modelsDir.path) {
            try? FileManager.default.createDirectory(at: modelsDir, withIntermediateDirectories: true)
        }
        
        if FileManager.default.fileExists(atPath: configFile.path) {
            self.isModelReady = true
            self.modelPath = modelsDir
            self.checkStatus = "Ready"
        } else {
            self.isModelReady = false
            self.modelPath = nil
            self.checkStatus = "Missing"
        }
    }
    
    public var modelsDirectory: URL {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".eliteagent/models/\(defaultModelID)")
    }
    
    // MARK: - Downloader Logic
    
    public func startModelDownload() {
        guard !isDownloading else { return }
        
        // MLX Community Mistral 4-bit repo files
        let baseURL = "https://huggingface.co/mlx-community/Mistral-7B-Instruct-v0.2-4bit-mlx/resolve/main/"
        let files = ["config.json", "tokenizer.model", "weights.npz"]
        
        downloadQueue = files.compactMap { URL(string: baseURL + $0) }
        isDownloading = true
        downloadNextInQueue()
    }
    
    private func downloadNextInQueue() {
        guard let nextURL = downloadQueue.first else {
            self.isDownloading = false
            self.checkModelStatus()
            return
        }
        
        self.currentDownloadTask = nextURL.lastPathComponent
        let task = downloadSession.downloadTask(with: nextURL)
        task.resume()
    }
}

// MARK: - URLSessionDownloadDelegate (Internal Isolation handling)

extension ModelSetupManager: URLSessionDownloadDelegate {
    public nonisolated func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
        let fileName = downloadTask.originalRequest?.url?.lastPathComponent ?? "unknown"
        
        // We must jump back to MainActor for file operations and state updates
        Task { @MainActor in
            let destination = self.modelsDirectory.appendingPathComponent(fileName)
            do {
                if FileManager.default.fileExists(atPath: destination.path) {
                    try FileManager.default.removeItem(at: destination)
                }
                try FileManager.default.moveItem(at: location, to: destination)
                
                if !self.downloadQueue.isEmpty {
                    self.downloadQueue.removeFirst()
                    self.downloadNextInQueue()
                }
            } catch {
                print("[ModelSetup] Failed to move file: \(error)")
                self.isDownloading = false
            }
        }
    }
    
    public nonisolated func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didWriteData bytesWritten: Int64, totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64) {
        let progress = Double(totalBytesWritten) / Double(totalBytesExpectedToWrite)
        Task { @MainActor in
            self.downloadProgress = progress
        }
    }
}
