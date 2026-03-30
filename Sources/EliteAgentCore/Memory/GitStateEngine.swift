import Foundation

public actor GitStateEngine {
    private var projectRoot: URL
    
    public init(projectRoot: URL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)) {
        self.projectRoot = projectRoot
    }
    
    public func setProjectRoot(_ path: String) {
        let expanded = NSString(string: path).expandingTildeInPath
        self.projectRoot = URL(fileURLWithPath: expanded)
    }
    
    public func commit(message: String) async throws {
        // First add all changes to stage
        let addProcess = Process()
        addProcess.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        addProcess.arguments = ["add", "-A"]
        addProcess.currentDirectoryURL = projectRoot
        
        try addProcess.run()
        addProcess.waitUntilExit()
        
        // Then commit
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        process.arguments = ["commit", "-m", message]
        process.currentDirectoryURL = projectRoot
        
        try process.run()
        process.waitUntilExit()
    }
    
    public static let shared = GitStateEngine()
    
    public func status() async throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        process.arguments = ["status", "-s"]
        process.currentDirectoryURL = projectRoot
        
        let pipe = Pipe()
        process.standardOutput = pipe
        try process.run()
        process.waitUntilExit()
        
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        return String(data: data, encoding: .utf8) ?? "No changes"
    }
    
    public func diff() async throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        process.arguments = ["diff"]
        process.currentDirectoryURL = projectRoot
        
        let pipe = Pipe()
        process.standardOutput = pipe
        try process.run()
        process.waitUntilExit()
        
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        return String(data: data, encoding: .utf8) ?? ""
    }
    
    public func revert(to hash: String) async throws {
        // As per PRD Madde 12, Orchestrator enforces approval logic globally before routing here
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        process.arguments = ["reset", "--hard", hash]
        process.currentDirectoryURL = projectRoot
        
        try process.run()
        process.waitUntilExit()
    }
}
