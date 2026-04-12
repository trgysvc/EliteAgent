import Foundation

/// PluginCraftEngine: EliteAgent'in "Recursive Evolution" yeteneğini sağlayan motor.
/// Ajan tarafından yazılan yeni Tool'ları çalışma zamanında (runtime) derler ve yükler.
public actor PluginCraftEngine {
    public static let shared = PluginCraftEngine()
    
    private let fileManager = FileManager.default
    private let pluginsDirectory: URL
    
    private init() {
        let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        self.pluginsDirectory = appSupport.appendingPathComponent("EliteAgent/Plugins")
        
        try? fileManager.createDirectory(at: pluginsDirectory, withIntermediateDirectories: true)
    }
    
    /// Yeni bir aracı (plugin) Swift kodu olarak alır, derler ve yükler.
    public func evolve(withSource source: String, toolName: String) async throws -> String {
        AgentLogger.logAudit(level: .info, agent: "PluginCraft", message: "🧬 Evolution starting for tool: \(toolName)")
        
        let toolDirectory = pluginsDirectory.appendingPathComponent(toolName)
        try fileManager.createDirectory(at: toolDirectory, withIntermediateDirectories: true)
        
        let sourceURL = toolDirectory.appendingPathComponent("\(toolName).swift")
        try source.write(to: sourceURL, atomically: true, encoding: .utf8)
        
        let libraryURL = toolDirectory.appendingPathComponent("lib\(toolName).dylib")
        
        // v14.2: Standalone Dynamic Compilation (Using PluginInterface for zero dependencies)
        let interfaceURL = pluginsDirectory.deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("Resources/PluginInterface.swift")
        let compileCommand = "swiftc -emit-library -o \(libraryURL.path) \(interfaceURL.path) \(sourceURL.path)"
        let compileResult = try await runShell(command: compileCommand)
        
        if compileResult.contains("error:") {
            throw ToolError.executionError("Compilation Failed: \(compileResult)")
        }
        
        // v14.4: Ad-hoc Code Signing (Hardening for Apple Silicon)
        let signCommand = "codesign -s - --force --options runtime \(libraryURL.path)"
        let signResult = try await runShell(command: signCommand)
        
        if !signResult.isEmpty && !signResult.contains("signed") {
            AgentLogger.logAudit(level: .warn, agent: "PluginCraft", message: "⚠️ Signing issue: \(signResult)")
        }
        
        AgentLogger.logAudit(level: .info, agent: "PluginCraft", message: "✅ Tool compiled and signed: \(libraryURL.lastPathComponent)")
        
        return "Evolve Successful: '\(toolName)' derlendi, ad-hoc imzalandı ve \(libraryURL.path) konumuna kaydedildi."
    }
    
    private func runShell(command: String) async throws -> String {
        return try await withCheckedThrowingContinuation { continuation in
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/bin/zsh")
            process.arguments = ["-c", command]
            
            let pipe = Pipe()
            process.standardOutput = pipe
            process.standardError = pipe
            
            do {
                try process.run()
                process.waitUntilExit()
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                continuation.resume(returning: String(data: data, encoding: .utf8) ?? "")
            } catch {
                continuation.resume(throwing: error)
            }
        }
    }
}
