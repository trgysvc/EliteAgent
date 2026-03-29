import Foundation
import EliteAgentCore

Task {
    let args = CommandLine.arguments
    guard args.count > 1 else {
        print("Usage: elite \"task description\"")
        exit(1)
    }
    
    let taskPrompt = args.dropFirst().joined(separator: " ")
    let orchestrator = await Orchestrator()
    
    do {
        try await orchestrator.submitTask(prompt: taskPrompt)
        print("✅ Task execution finished.")
        exit(0)
    } catch {
        print("❌ Execution Error: \(error)")
        exit(1)
    }
}

// Modern Swift 6 replacement for RunLoop.main.run()
dispatchMain()
