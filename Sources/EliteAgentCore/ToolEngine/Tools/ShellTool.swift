import Foundation

public struct ShellTool: AgentTool, Sendable {
    public let name = "shell_exec"
    public let summary = "Directly execute zsh/osascript commands."
    public let description = "Execute a shell command directly via /bin/zsh. Supports osascript for AppleScript. Parameter: command (string)."
    public let ubid = 32 // Token 'A' in Qwen 2.5
    
    public init() {}
    
    public func execute(params: [String: AnyCodable], session: Session) async throws -> String {
        guard let command = params["command"]?.value as? String else {
            throw ToolError.missingParameter("'command' parameter is required.")
        }
        
        // Safety Check via LogicGate (Phase 1 Hardening)
        let risk = LogicGate.shared.check(command: command)
        if risk.isDangerous {
            let errorMsg = """
            [SAFETY BLOCK] Command rejected: \(command)
            Reason: \(risk.reason ?? "Dangerous execution detected.")
            Suggestion: Use built-in Swift tools or standard whitelisted commands.
            """
            throw ToolError.executionError(errorMsg)
        }
        
        print("[SHELL] Executing: \(command)")
        
        return try await withCheckedThrowingContinuation { continuation in
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/bin/zsh")
            process.arguments = ["-c", command]
            process.currentDirectoryURL = session.workspaceURL
            
            let outputPipe = Pipe()
            let errorPipe = Pipe()
            process.standardOutput = outputPipe
            process.standardError = errorPipe
            
            do {
                try process.run()
            } catch {
                continuation.resume(throwing: ToolError.executionError("Failed to launch process: \(error.localizedDescription)"))
                return
            }
            
            // Run waitUntilExit on a background thread to avoid blocking the actor
            DispatchQueue.global(qos: .userInitiated).async {
                process.waitUntilExit()
                
                let outputData = outputPipe.fileHandleForReading.readDataToEndOfFile()
                let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()
                
                let output = String(data: outputData, encoding: .utf8) ?? ""
                let errorOutput = String(data: errorData, encoding: .utf8) ?? ""
                
                let exitCode = process.terminationStatus
                
                if exitCode != 0 && !errorOutput.isEmpty {
                    let fullResult = output.isEmpty ? errorOutput : "\(output)\n[STDERR]: \(errorOutput)"
                    continuation.resume(returning: fullResult)
                } else {
                    continuation.resume(returning: output.isEmpty ? "(command completed, no output)" : output)
                }
            }
        }
    }
}
