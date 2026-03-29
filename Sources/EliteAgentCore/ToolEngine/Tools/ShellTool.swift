import Foundation

// NOTE: SandboxProtocol is defined in EliteAgentXPC/main.swift (the XPC service).
// We re-declare the Objective-C protocol here so the client-side NSXPCInterface
// can reference it without a shared framework. Both declarations must stay identical.
@objc protocol SandboxProtocol {
    func runCommand(_ command: String, inDirectory directory: String?, reply: @escaping (String?, Error?) -> Void)
}

public struct ShellTool: AgentTool, Sendable {
    public let name = "shell_exec"
    public let description = "Execute a shell command via sandboxed XPC service."
    
    public init() {}
    
    public func execute(params: [String: AnyCodable], session: Session) async throws -> String {
        guard let command = params["command"]?.value as? String else {
            throw NSError(domain: "ShellTool", code: 3, userInfo: [NSLocalizedDescriptionKey: "Missing 'command' parameter"])
        }
        
        let workspacePath = session.workspaceURL.path
        
        // Enforce XPC boundary execution
        let connection = NSXPCConnection(serviceName: "com.trgysvc.EliteAgent.XPC")
        connection.remoteObjectInterface = NSXPCInterface(with: SandboxProtocol.self)
        connection.resume()
        
        return try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<String, Error>) in
            let proxy = connection.remoteObjectProxyWithErrorHandler { error in
                print("[XPC] ShellTool connection error: \(error)")
                continuation.resume(throwing: error)
            } as? SandboxProtocol
            
            guard let proxy = proxy else {
                continuation.resume(throwing: NSError(domain: "ShellTool", code: 1, userInfo: [NSLocalizedDescriptionKey: "Failed to connect to XPC Service"]))
                return
            }
            
            proxy.runCommand(command, inDirectory: workspacePath) { result, error in
                if let error = error {
                    continuation.resume(throwing: error)
                } else if let result = result {
                    continuation.resume(returning: result)
                } else {
                    continuation.resume(throwing: NSError(domain: "ShellTool", code: 2, userInfo: nil))
                }
            }
        }
    }
}
