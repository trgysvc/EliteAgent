import Foundation
import EliteAgentCore

// Top-level async entry point
let task = Task {
    let args = CommandLine.arguments
    guard args.count > 1 else {
        print("Usage: elite \"task description\"")
        exit(1)
    }
    let taskPrompt = args.dropFirst().joined(separator: " ")
    let orchestrator = Orchestrator()
    await orchestrator.start()
    
    do {
        try await orchestrator.submitTask(prompt: taskPrompt)
        print("✅ Task execution finished.")
        exit(0)
    } catch {
        print("❌ Execution Error: \(error)")
        exit(1)
    }
}

// Keep alive until task completes
RunLoop.main.run()
