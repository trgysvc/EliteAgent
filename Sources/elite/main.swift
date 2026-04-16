import Foundation
import EliteAgentCore

@MainActor
func runCLI() async {
    let args = CommandLine.arguments
    let flags = ["--cloud-only", "--local-only", "--strict-local", "--benchmark"]
    
    let isCloudOnly = args.contains("--cloud-only")
    let isLocalOnly = args.contains("--local-only")
    let strictLocal = args.contains("--strict-local")
    let isBenchmark = args.contains("--benchmark")
    
    print("[CLI] Initializing EliteAgent Orchestrator...")
    let orchestrator = Orchestrator()
    
    // v30.0: Auto-prime the Brain (LLM) if not already primed
    print("[CLI] Priming the Titan Engine (vRAM Check)...")
    let modelDir = PathConfiguration.shared.modelsURL.appendingPathComponent("qwen-2.5-7b-4bit")
    if FileManager.default.fileExists(atPath: modelDir.path) {
        do {
            try await InferenceActor.shared.loadModel(at: modelDir)
            print("✅ [CLI] Brain Synchronized: Qwen-2.5-7b-4bit loaded.")
        } catch {
            print("⚠️ [CLI] Primary Brain failed to load. Falling back to safe mode.")
        }
    }
    
    do {
        if strictLocal {
            print("[CLI] Strict Local Mode ACTIVE. Bypassing all fallbacks.")
        }
        
        let taskPrompt = args.filter { !flags.contains($0) }.dropFirst().joined(separator: " ")
        
        if taskPrompt.isEmpty && !isBenchmark {
            print("EliteAgent CLI v30.0")
            print("Usage: elite <task description> [--cloud-only|--local-only|--strict-local|--benchmark]")
            return
        }
        
        print("Submiting task to Orchestrator: '\(taskPrompt)'")
        
        // Disable interactive shell behavior for CLI direct tasks
        let finalPrompt = isBenchmark ? "Write a comprehensive 1000-word philosophical analysis of Apple Silicon architecture, focusing on the M4's Neural Engine and Metal utilization." : taskPrompt
        
        if isBenchmark {
            print("\n🚀 [BENCHMARK] Sustainable Performance Audit ACTIVE.")
            print("🚀 [BENCHMARK] Target: 1000+ Tokens | Hardware: Apple M4 GPU/ANE")
            print(M4PerformanceAudit.checkCapacity())
            print("────────────────────────────────────────────────────────────")
        }

        try await orchestrator.submitTask(
            prompt: finalPrompt,
            strictLocal: isLocalOnly || strictLocal,
            promptOnFallback: !isLocalOnly && !strictLocal
        )
        
        // Standard turn-wait for direct tasks
        // In a more complex CLI we'd observe the state manager here
        print("\n✅ Task execution finished.")
        
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
