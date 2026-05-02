import Foundation
import EliteAgentCore

/// v31.3: Official v3-Native EliteService (XPC Daemon)
/// Swift 6 Concurrency Compliant & XPC Isolated.
class EliteService: NSObject, EliteServiceProtocol, NSXPCListenerDelegate {
    private var orchestrator: Orchestrator?
    private let listener: NSXPCListener
    
    override init() {
        // v30.0: UNO Mach Service Listener
        self.listener = NSXPCListener(machServiceName: "com.eliteagent.service")
        super.init()
        self.listener.delegate = self
    }
    
    @MainActor
    func start() async {
        print("🛡 [EliteService] Initializing Titan Engine...")
        
        // Initialize the MainActor-isolated Orchestrator
        self.orchestrator = Orchestrator()
        
        let modelDir = PathConfiguration.shared.modelsURL.appendingPathComponent("qwen-2.5-7b-4bit")
        if FileManager.default.fileExists(atPath: modelDir.path) {
            do {
                try await InferenceActor.shared.loadModel(at: modelDir)
                print("✅ [EliteService] Brain Synchronized: Qwen-2.5-7b-4bit primed in VRAM.")
            } catch {
                print("⚠️ [EliteService] Primary Brain failed to load: \(error)")
            }
        }
        
        print("📡 [EliteService] Listening for Mach Service connections: com.eliteagent.service...")
        self.listener.resume()
        
        while true {
            try? await Task.sleep(nanoseconds: 1_000_000_000)
        }
    }
    
    // MARK: - EliteServiceProtocol
    
    func submitTask(prompt: String, withReply completion: @escaping @Sendable (String?, Error?) -> Void) {
        let currentOrchestrator = self.orchestrator
        Task { @MainActor in
            guard let orchestrator = currentOrchestrator else {
                completion(nil, NSError(domain: "EliteService", code: 503, userInfo: [NSLocalizedDescriptionKey: "Orchestrator not ready."]))
                return
            }
            
            do {
                print("📩 [EliteService] Task Received: \(prompt)")
                try await orchestrator.submitTask(prompt: prompt, strictLocal: true, promptOnFallback: false)
                completion("Task submitted to Orchestrator.", nil)
            } catch {
                completion(nil, error)
            }
        }
    }
    
    func getStatus(withReply completion: @escaping @Sendable (String?, Error?) -> Void) {
        Task {
            let isLoaded = await InferenceActor.shared.isModelLoaded
            let status = "EliteService v7.1 | Engine: \(isLoaded ? "Primed" : "Idle")"
            completion(status, nil)
        }
    }
    
    func reprimeEngine(withReply completion: @escaping @Sendable (Bool, Error?) -> Void) {
        Task {
            do {
                let modelDir = PathConfiguration.shared.modelsURL.appendingPathComponent("qwen-2.5-7b-4bit")
                try await InferenceActor.shared.loadModel(at: modelDir)
                completion(true, nil)
            } catch {
                completion(false, error)
            }
        }
    }
    
    // MARK: - NSXPCListenerDelegate
    
    func listener(_ listener: NSXPCListener, shouldAcceptNewConnection newConnection: NSXPCConnection) -> Bool {
        newConnection.exportedInterface = NSXPCInterface(with: EliteServiceProtocol.self)
        newConnection.exportedObject = self
        newConnection.resume()
        return true
    }
}

// MARK: - Entry Point
let service = EliteService()
await service.start()
