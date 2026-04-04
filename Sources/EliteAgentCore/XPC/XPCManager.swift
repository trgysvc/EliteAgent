import Foundation

/// Manages the lifecycle of the EliteAgentXPC connection.
public actor XPCManager {
    public static let shared = XPCManager()
    
    private var connection: NSXPCConnection?
    private let serviceName = "com.trgysvc.EliteAgent.XPC" // Standard for embedded XPC Services
    
    private init() {}
    
    /// Restarts the XPC connection and attempts a handshake.
    /// - Throws: Error if the connection cannot be established.
    public func restart() throws {
        AgentLogger.logAudit(level: .info, agent: "system", message: "Restarting XPC Connection...")
        
        // 1. Invalidate current
        connection?.invalidate()
        connection = nil
        
        // 2. Re-initialize
        let newConnection = NSXPCConnection(serviceName: serviceName)
        
        newConnection.remoteObjectInterface = NSXPCInterface(with: NSProtocolFromString("SandboxProtocol") ?? SandboxProtocol.self)
        
        newConnection.interruptionHandler = {
            AgentLogger.logAudit(level: .warn, agent: "system", message: "XPC Connection Interrupted.")
        }
        
        newConnection.invalidationHandler = {
            AgentLogger.logAudit(level: .info, agent: "system", message: "XPC Connection Invalidated.")
        }
        
        newConnection.resume()
        
        // 3. Test Handshake (Optional but recommended for 'restart')
        _ = newConnection.remoteObjectProxy as? SandboxProtocol
        
        self.connection = newConnection
        AgentLogger.logAudit(level: .info, agent: "system", message: "XPC Connection Restored.")
    }
    
    /// Returns the active remote object proxy.
    public func getProxy() async throws -> SandboxProtocol {
        if connection == nil {
            try restart()
        }
        
        guard let proxy = connection?.remoteObjectProxy as? SandboxProtocol else {
            throw NSError(domain: "XPCManager", code: 501, userInfo: [NSLocalizedDescriptionKey: "XPC Proxy is currently unavailable."])
        }
        
        return proxy
    }
    
    /// Ensures the XPC connection is established, with built-in retry logic.
    public func ensureConnected() async {
        // v8.4: Robust retry logic for initial handshakes
        for attempt in 1...3 {
            do {
                if connection == nil {
                    try restart()
                    AgentLogger.logAudit(level: .info, agent: "system", message: "XPC Handshake Success (Attempt \(attempt))")
                }
                return
            } catch {
                AgentLogger.logAudit(level: .warn, agent: "system", message: "XPC Handshake Failed (Attempt \(attempt)): \(error.localizedDescription)")
                if attempt < 3 {
                    try? await Task.sleep(nanoseconds: 500_000_000) // 500ms
                }
            }
        }
    }
    
    /// Checks if the XPC connection is established (non-blocking).
    public func isServiceAvailable() -> Bool {
        return connection != nil
    }
}

// Protocol re-definition if not visible (bridging)
@objc public protocol SandboxProtocol {
    func runCommand(_ command: String, inDirectory directory: String?, reply: @escaping (String?, Error?) -> Void)
}
