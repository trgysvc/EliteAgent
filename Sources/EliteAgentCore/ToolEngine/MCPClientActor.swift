import Foundation
import MCP
import System

/// v7.0 Stability: Session-Scoped MCP Client Actor
/// Manages Model Context Protocol sessions for external tool integrations.
public actor MCPClientActor {
    public static let shared = MCPClientActor()
    
    private struct SessionKey: Hashable {
        let sessionId: UUID
        let serverName: String
    }
    
    /// Internal storage for an active MCP session and its underlying process.
    private struct ClientSession {
        let client: Client
        let transport: StdioTransport
        let process: Process
    }
    
    private var activeSessions: [SessionKey: ClientSession] = [:]
    private var lastActivity: [SessionKey: Date] = [:]
    
    private init() {
        // v7.0: Start the sweep timer in a detached task.
        Task {
            await startSweepTimer()
        }
    }
    
    private func startSweepTimer() async {
        while !Task.isCancelled {
            try? await Task.sleep(nanoseconds: 60 * 1_000_000_000) // 60s sweep
            sweepIdleSessions()
        }
    }
    
    public func sweepIdleSessions() {
        let now = Date()
        let timeout: TimeInterval = 600 // 10 minutes
        
        for (key, date) in lastActivity {
            if now.timeIntervalSince(date) > timeout {
                AgentLogger.logAudit(level: .info, agent: "MCP-Actor", message: "🧹 Deallocating idle session: \(key.serverName) (Session: \(key.sessionId))")
                if let session = activeSessions.removeValue(forKey: key) {
                    Task {
                        await session.transport.disconnect()
                        session.process.terminate()
                    }
                }
                lastActivity.removeValue(forKey: key)
            }
        }
    }
    
    /// Retrieves an existing session or spawns a new one for the given server.
    private func getOrCreateSession(sessionId: UUID, serverName: String) async throws -> ClientSession {
        let key = SessionKey(sessionId: sessionId, serverName: serverName)
        if let session = activeSessions[key] {
            lastActivity[key] = Date()
            return session
        }
        
        // 1. Locate server config in Vault
        let vault = await VaultManager.shared.config
        guard let config = vault.mcpServers?.first(where: { $0.name == serverName }) else {
            throw NSError(domain: "MCPClientActor", code: 404, userInfo: [NSLocalizedDescriptionKey: "MCP Server '\(serverName)' not configured in vault."])
        }
        
        // 2. Spawn process
        let process = Process()
        process.executableURL = URL(fileURLWithPath: config.command)
        process.arguments = config.args
        process.environment = config.env
        
        let stdinPipe = Pipe()
        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        
        process.standardInput = stdinPipe
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe
        
        try process.run()
        
        // 3. Setup StdioTransport
        // v7.0: Use raw file descriptors from pipes to bridge into MCP SDK.
        let inputFD = FileDescriptor(rawValue: stdoutPipe.fileHandleForReading.fileDescriptor)
        let outputFD = FileDescriptor(rawValue: stdinPipe.fileHandleForWriting.fileDescriptor)
        
        let transport = StdioTransport(input: inputFD, output: outputFD)
        let client = Client(name: "EliteAgent", version: "7.0.0")
        
        // 4. Connect (Handshake: initialize -> initialized)
        try await client.connect(transport: transport)
        
        let session = ClientSession(client: client, transport: transport, process: process)
        activeSessions[key] = session
        lastActivity[key] = Date()
        
        // Capture stderr in a background task for logging
        Task { [weak stderrPipe] in
            guard let pipe = stderrPipe else { return }
            for try await line in pipe.fileHandleForReading.bytes.lines {
                AgentLogger.logAudit(level: .info, agent: "MCP-Server:\(serverName)", message: " [stderr] \(line)")
            }
        }
        
        return session
    }
    
    /// Executes a tool on a specific MCP server.
    public func executeTool(sessionId: UUID, serverName: String, tool: String, params: [String: Any]) async throws -> String {
        let session = try await getOrCreateSession(sessionId: sessionId, serverName: serverName)
        
        // v7.0: Bridge UNO Binary (via params) to MCP JSON-RPC (via SDK CallTool)
        // Note: The SDK CallTool.request takes [String: Value] where Value is a JSON-like enum.
        // We'll use a simplified mapping for now.
        
        var arguments: [String: Value] = [:]
        for (key, val) in params {
            if let str = val as? String { arguments[key] = .string(str) }
            else if let num = val as? Double { arguments[key] = .double(num) }
            else if let num = val as? Int { arguments[key] = .int(num) }
            else if let bool = val as? Bool { arguments[key] = .bool(bool) }
        }
        
        let (content, isError) = try await session.client.callTool(name: tool, arguments: arguments)
        
        let resultString = content.map { item -> String in
            switch item {
            case .text(let text, _, _): return text
            case .image(let data, let mimeType, _, _): return "[Image: \(mimeType)] (\(data.count) bytes)"
            case .audio(let data, let mimeType, _, _): return "[Audio: \(mimeType)] (\(data.count) bytes)"
            case .resource(let res, _, _): return "[Resource: \(res.uri)]"
            case .resourceLink(let uri, let name, _, _, _, _): return "[Resource Link: \(name) (\(uri))]"
            }
        }.joined(separator: "\n")
        
        if isError == true {
            throw NSError(domain: "MCPClientActor", code: 500, userInfo: [NSLocalizedDescriptionKey: "MCP Tool Error: \(resultString)"])
        }
        
        return resultString
    }
}
