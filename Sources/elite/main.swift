import Foundation
import EliteAgentCore

@MainActor
func runCLI() async {
    let args = CommandLine.arguments
    let flags = ["--cloud-only", "--local-only", "--strict-local", "--benchmark"]
    
    _ = args.contains("--cloud-only")
    _ = args.contains("--local-only")
    _ = args.contains("--strict-local")
    let isBenchmark = args.contains("--benchmark")
    
    print("[CLI] Connecting to EliteService...")
    
    let connection = NSXPCConnection(machServiceName: "com.eliteagent.service", options: .privileged)
    connection.remoteObjectInterface = NSXPCInterface(with: EliteServiceProtocol.self)
    connection.resume()
    
    guard let service = connection.remoteObjectProxyWithErrorHandler({ error in
        print("❌ [CLI] Connection Error: \(error.localizedDescription)")
        print("⚠️ Ensure EliteService is running (launchctl list | grep elite).")
    }) as? EliteServiceProtocol else {
        print("❌ [CLI] Failed to establish XPC bridge.")
        return
    }
    
    do {
        let taskPrompt = args.filter { !flags.contains($0) }.dropFirst().joined(separator: " ")
        
        if taskPrompt.isEmpty && !isBenchmark {
            service.getStatus { status, error in
                if let status = status {
                    print("\n📡 Service Status: \(status)")
                }
            }
            // Allow time for reply
            try await Task.sleep(nanoseconds: 500_000_000)
            print("\nUsage: elite <task description> [--cloud-only|--local-only|--strict-local|--benchmark]")
            return
        }
        
        print("🚀 Sending task to EliteService: '\(taskPrompt)'")
        
        service.submitTask(prompt: taskPrompt) { response, error in
            if let error = error {
                print("❌ [Service Error]: \(error.localizedDescription)")
            } else if let response = response {
                print("✅ [Service]: \(response)")
            }
        }
        
        // Wait for acknowledgement
        try await Task.sleep(nanoseconds: 1_000_000_000)
        
    } catch {
        print("❌ CLI Error: \(error.localizedDescription)")
    }
}

// Global scope initialization (Swift 6)
Task {
    await runCLI()
}

// Keep-alive for Async task
RunLoop.main.run(until: .distantFuture)
