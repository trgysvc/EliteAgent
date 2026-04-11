import Foundation
import EliteAgentCore

@MainActor
func testTools() async {
    print("🚀 [TOOL TEST] Starting Tool Registry Direct Test...")
    
    let registry = ToolRegistry.shared
    
    // Trigger registration by initializing Orchestrator (minimal)
    _ = Orchestrator() 
    
    let tools = registry.listTools()
    print("✅ Total Tools Registered: \(tools.count)")
    
    // Test 1: get_system_info
    print("\n🧪 Test 1: get_system_info")
    do {
        let session = Session(workspaceURL: URL(fileURLWithPath: "/tmp"), config: .default, complexity: 1)
        let result = try await registry.execute(toolCall: ToolCall(tool: "get_system_info", params: [:]), session: session)
        print("✅ Result: \(result.prefix(100))...")
    } catch {
        print("❌ Error: \(error)")
    }
    
    // Test 2: calculator
    print("\n🧪 Test 2: calculator (2 + 2)")
    do {
        let session = Session(workspaceURL: URL(fileURLWithPath: "/tmp"), config: .default, complexity: 1)
        let result = try await registry.execute(toolCall: ToolCall(tool: "calculator", params: ["expression": AnyCodable("2 + 2")]), session: session)
        print("✅ Result: \(result)")
    } catch {
        print("❌ Error: \(error)")
    }

    print("\n✨ Tool Registry Direct Test Completed.")
}

// In a real script this would be different, but for now we just want to verify logic.
// We'll run this via 'swift run' if we can link it, or just use it as code reference.
