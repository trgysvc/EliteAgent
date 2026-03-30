import Foundation
import Combine

@MainActor
public class ModelSetupManager: ObservableObject {
    public static let shared = ModelSetupManager()
    
    @Published public var isModelReady: Bool = false
    @Published public var modelPath: URL?
    @Published var checkStatus: String = "Checking models..."
    
    private let defaultModelID = "mistral-7b-instruct-v0.3-4bit"
    private var timer: Timer?
    
    private init() {
        checkModelStatus()
        // Periodically check if the user dropped the files in the directory
        timer = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: true) { _ in
            Task { @MainActor in
                self.checkModelStatus()
            }
        }
    }
    
    public func checkModelStatus() {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let modelsDir = home.appendingPathComponent(".eliteagent/models/\(defaultModelID)")
        let configFile = modelsDir.appendingPathComponent("config.json")
        
        // Ensure directory exists
        if !FileManager.default.fileExists(atPath: modelsDir.path) {
            try? FileManager.default.createDirectory(at: modelsDir, withIntermediateDirectories: true)
        }
        
        if FileManager.default.fileExists(atPath: configFile.path) {
            DispatchQueue.main.async {
                self.isModelReady = true
                self.modelPath = modelsDir
                self.checkStatus = "Ready"
            }
        } else {
            DispatchQueue.main.async {
                self.isModelReady = false
                self.modelPath = nil
                self.checkStatus = "Missing"
            }
        }
    }
    
    public var modelsDirectory: URL {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".eliteagent/models/\(defaultModelID)")
    }
}
