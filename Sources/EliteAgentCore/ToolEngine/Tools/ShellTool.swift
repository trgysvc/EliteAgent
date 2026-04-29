import Foundation

public struct ShellTool: AgentTool, Sendable {
    public let name = "shell_exec"
    public let summary = "Execute zsh/terminal commands."
    public let description = "THIS IS YOUR SOLE AND ONLY TERMINAL TOOL. Use it for all shell, zsh, and terminal-level commands. Parameter: command (string)."
    public let ubid: Int128 = 32 // Token 'A' in Qwen 2.5
    
    public init() {}
    
    public func execute(params: [String: AnyCodable], session: Session) async throws(AgentToolError) -> String {
        guard let command = params["command"]?.value as? String else {
            throw AgentToolError.missingParameter("'command' parameter is required.")
        }
        
        // Safety Check via LogicGate (Phase 1 Hardening)
        let risk = LogicGate.shared.check(command: command)
        if risk.isDangerous {
            let errorMsg = """
            [SAFETY BLOCK] Command rejected: \(command)
            Reason: \(risk.reason ?? "Dangerous execution detected.")
            Suggestion: Use built-in Swift tools or standard whitelisted commands.
            """
            throw AgentToolError.executionError(errorMsg)
        }
        
        print("[SHELL] Executing: \(command)")
        
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/zsh")
        process.arguments = ["-c", command]
        process.currentDirectoryURL = session.workspaceURL
        
        let outputPipe = Pipe()
        let errorPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = errorPipe
        
        do {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                process.terminationHandler = { _ in
                    continuation.resume()
                }
                do {
                    try process.run()
                } catch {
                    continuation.resume(throwing: error)
                }
            }
            
            let outputData = try outputPipe.fileHandleForReading.readToEnd() ?? Data()
            let errorData = try errorPipe.fileHandleForReading.readToEnd() ?? Data()
            
            let output = String(data: outputData, encoding: .utf8) ?? ""
            let errorOutput = String(data: errorData, encoding: .utf8) ?? ""
            
            let exitCode = process.terminationStatus
            
            if exitCode != 0 {
                let combinedOutput = [output, errorOutput]
                    .filter { !$0.isEmpty }
                    .joined(separator: "\n[STDERR]: ")
                let taggedResult = "[SHELL_ERROR] Exit \(exitCode): \(combinedOutput)"
                AgentLogger.logAudit(level: .warn, agent: "ShellTool", message: taggedResult)
                return taggedResult
            } else {
                return output.isEmpty ? "(command completed, no output)" : output
            }
        } catch {
            throw AgentToolError.executionError("Failed to execute process: \(error.localizedDescription)")
        }
    }
}
