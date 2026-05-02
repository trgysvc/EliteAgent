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
    
    init(executor: UNOSandboxExecutor) {
        self.executor = executor
        super.init()
        
        // v13.1: Initialize and Scan Plugins
        let signatures = PluginManager.shared.scanAndLoad()
        AgentLogger.logInfo("[UNO-XPC] Plugin scan complete. \(signatures.count) tools loaded.")
    }
    
    func performRemoteAction(data: Data, reply: @escaping @Sendable (Data?, Data?) -> Void) {
        Task {
            do {
                // v13.8: Swift Native Binary Decoding (PLST)
                let action = try PropertyListDecoder().decode(UNOActionWrapper.self, from: data)
                
                // v13.8: Schema Version Validation
                let currentVersion = 1
                if action.version > currentVersion {
                    AgentLogger.logAudit(level: .warn, agent: "UNO-XPC", message: "Incoming action has higher version (V\(action.version)) than service (V\(currentVersion)). Processing with caution.")
                }
                
                let response = try await executor.execute(action: action)
                
                // v13.8: Binary Encoding of result
                let encoder = PropertyListEncoder()
                encoder.outputFormat = .binary
                let responseData = try encoder.encode(response)
                
                reply(responseData, nil)
            } catch {
                AgentLogger.logAudit(level: .error, agent: "UNO-XPC", message: "Binary decoding/execution failed: \(error.localizedDescription)")
                reply(nil, error.localizedDescription.data(using: .utf8))
            }
        }
    }

    func performSharedAction(shmem: FileHandle, size: Int, reply: @escaping @Sendable (Data?, Data?) -> Void) {
        Task {
            do {
                // v7.0 Stability: Map shared memory pointer directly
                let fd = shmem.fileDescriptor
                let pointer = mmap(nil, size, PROT_READ, MAP_SHARED, fd, 0)
                guard pointer != MAP_FAILED else {
                    reply(nil, "XPC_SHMEM_MAP_FAILED".data(using: .utf8))
                    return
                }
                defer { munmap(pointer, size) }
                
                let data = Data(bytesNoCopy: pointer!, count: size, deallocator: .none)
                let action = try PropertyListDecoder().decode(UNOActionWrapper.self, from: data)
                
                let response = try await executor.execute(action: action)
                
                let encoder = PropertyListEncoder()
                encoder.outputFormat = .binary
                let responseData = try encoder.encode(response)
                
                reply(responseData, nil)
            } catch {
                AgentLogger.logAudit(level: .error, agent: "UNO-XPC", message: "Shared memory execution failed: \(error.localizedDescription)")
                reply(nil, error.localizedDescription.data(using: .utf8))
            }
        }
    }

    func performMachAction(shmem: FileHandle, size: Int, signalPort: NSMachPort, reply: @escaping @Sendable (Data?, Data?) -> Void) {
        let port = signalPort.machPort
        Task {
            do {
                let fd = shmem.fileDescriptor
                let pointer = mmap(nil, size, PROT_READ | PROT_WRITE, MAP_SHARED, fd, 0)
                guard pointer != MAP_FAILED else {
                    reply(nil, "XPC_SHMEM_MAP_FAILED".data(using: .utf8))
                    return
                }
                defer { munmap(pointer, size) }
                
                let data = Data(bytesNoCopy: pointer!, count: size, deallocator: .none)
                let action = try PropertyListDecoder().decode(UNOActionWrapper.self, from: data)
                
                let response = try await executor.execute(action: action)
                
                // Write response back to shared memory if there's space, or just reply via XPC
                // For Mach flow, we signal the port to indicate 'Processing Done'
                let encoder = PropertyListEncoder()
                encoder.outputFormat = .binary
                let responseData = try encoder.encode(response)
                
                if responseData.count <= size {
                    responseData.withUnsafeBytes { ptr in
                        pointer?.copyMemory(from: ptr.baseAddress!, byteCount: responseData.count)
                    }
                    // v7.1: Fire Mach Signal
                    MachSignaler.signal(port: port)
                    reply(nil, nil) // Success, data is in shmem
                } else {
                    reply(responseData, nil) // Fallback to standard XPC if response is larger
                }
            } catch {
                AgentLogger.logAudit(level: .error, agent: "UNO-XPC", message: "Mach memory execution failed: \(error.localizedDescription)")
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

let executor = UNOSandboxExecutor(actorSystem: UNODistributedActorSystem.shared)
let delegate = UNOXPCService(executor: executor)
let listener = NSXPCListener.service()
listener.delegate = delegate
listener.resume()
RunLoop.main.run()
