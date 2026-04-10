import Foundation
import Distributed
import EliteAgentCore

/// v13.7: UNO Distributed Tool Executor Actor (Stabilized)
/// This is the native implementation that runs inside the XPC sandbox.
public distributed actor UNOSandboxExecutor {
    public typealias ActorSystem = UNODistributedActorSystem
    
    public distributed func execute(action: UNOActionWrapper) async throws -> UNOResponse {
        AgentLogger.logInfo("[UNO-XPC] Executing action: \(action.toolID)")
        
        // v13.1: Check Dynamic Plugins first
        if PluginManager.shared.loadedPlugins[action.toolID] != nil {
            return try await PluginManager.shared.executePlugin(id: action.toolID, action: action)
        }
        
        // Legacy fallback
        if action.toolID == "shell_exec" {
            let command = action.params["command"]?.value as? String ?? ""
            let result = try await runLegacyCommand(command)
            return UNOResponse(result: result)
        }
        
        return UNOResponse(result: "", error: "Tool \(action.toolID) not yet implemented in UNO.")
    }
    
    private func runLegacyCommand(_ command: String) async throws -> String {
        let prohibited = ["rm -rf /", "sudo rm -rf", "chmod -R 777 /"]
        guard !prohibited.contains(where: { command.contains($0) }) else {
            throw NSError(domain: "SandboxError", code: 403, userInfo: [NSLocalizedDescriptionKey: "Forbidden command"])
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/zsh")
        process.arguments = ["-c", command]

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe

        return try await withCheckedThrowingContinuation { continuation in
            process.terminationHandler = { proc in
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                let output = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                continuation.resume(returning: output)
            }
            
            do {
                try process.run()
            } catch {
                continuation.resume(throwing: error)
            }
        }
    }
}

/// XPC Service Entry Point
final class UNOXPCService: NSObject, NSXPCListenerDelegate, UNORemoteProxy, @unchecked Sendable {
    let executor: UNOSandboxExecutor
    
    override init() {
        self.executor = UNOSandboxExecutor(actorSystem: UNODistributedActorSystem.shared)
        super.init()
        
        // v13.1: Initialize and Scan Plugins
        let signatures = PluginManager.shared.scanAndLoad()
        AgentLogger.logInfo("[UNO-XPC] Plugin scan complete. \(signatures.count) tools loaded.")
    }
    
    func performRemoteAction(data: Data, reply: @escaping @Sendable (Data?, Data?) -> Void) {
        Task {
            do {
                let action = try JSONDecoder().decode(UNOActionWrapper.self, from: data)
                let response = try await executor.execute(action: action)
                let responseData = try JSONEncoder().encode(response)
                reply(responseData, nil)
            } catch {
                reply(nil, error.localizedDescription.data(using: .utf8))
            }
        }
    }

    func listener(_ listener: NSXPCListener, shouldAcceptNewConnection newConnection: NSXPCConnection) -> Bool {
        newConnection.exportedInterface = NSXPCInterface(with: UNORemoteProxy.self)
        newConnection.exportedObject = self
        newConnection.resume()
        return true
    }
}

let delegate = UNOXPCService()
let listener = NSXPCListener.service()
listener.delegate = delegate
listener.resume()
RunLoop.main.run()
