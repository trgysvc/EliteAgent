import Foundation

@objc public protocol SandboxProtocol {
    func runCommand(_ command: String, reply: @escaping (String?, Error?) -> Void)
}

public struct ShellTool: Sendable {
    public init() {}
    
    public func execute(_ command: String) async throws -> String {
        // Enforce XPC boundary execution
        let connection = NSXPCConnection(serviceName: "com.eliteagent.sandbox")
        connection.remoteObjectInterface = NSXPCInterface(with: SandboxProtocol.self)
        connection.resume()
        
        guard let proxy = connection.remoteObjectProxyWithErrorHandler({ error in
            print("XPC Connection Error: \(error)")
        }) as? SandboxProtocol else {
            throw NSError(domain: "ShellTool", code: 1, userInfo: [NSLocalizedDescriptionKey: "Failed to connect to XPC Service"])
        }
        
        return try await withCheckedThrowingContinuation { continuation in
            proxy.runCommand(command) { result, error in
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
