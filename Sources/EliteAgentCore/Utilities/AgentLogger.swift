import Foundation

public enum LogLevel: String, Sendable {
    case info = "INFO"
    case warn = "WARN"
    case error = "ERROR"
    case security = "SECURITY"
}

/// v10.5.6: High-Performance Sequential Log Worker
/// Prevents lock contention and file-system bridge freezes by serializing I/O.
actor LogWorker {
    static let shared = LogWorker()
    private var fileHandles: [String: FileHandle] = [:]
    
    func write(fileName: String, content: String) {
        let logPath = PathConfiguration.shared.logsURL.appendingPathComponent(fileName)
        let dir = logPath.deletingLastPathComponent()
        
        do {
            if !FileManager.default.fileExists(atPath: dir.path) {
                try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            }
            
            let data = (content + "\n").data(using: .utf8) ?? Data()
            
            if !FileManager.default.fileExists(atPath: logPath.path) {
                try data.write(to: logPath)
                print("[AgentLogger] Created new log file: \(logPath.path)")
            } else {
                let handle: FileHandle
                if let existing = fileHandles[fileName] {
                    handle = existing
                } else {
                    let newHandle = try FileHandle(forWritingTo: logPath)
                    fileHandles[fileName] = newHandle
                    handle = newHandle
                    print("[AgentLogger] Primary Log Path: \(logPath.path)")
                }
                
                try handle.seekToEnd()
                handle.write(data)
                // v10.5.6: Synchronize for OS visibility without closing
                try handle.synchronize()
            }
        } catch {
            // v10.5.6: Fallback to Console on Disk Failure
            print("🛑 [AgentLogger ERROR] Failed to write to \(fileName): \(error.localizedDescription)")
            print("📝 [FALLBACK] \(content)")
        }
    }
    
    deinit {
        for handle in fileHandles.values {
            try? handle.close()
        }
    }
}

public struct AgentLogger: Sendable {
    public static func logAudit(level: LogLevel, agent: String, message: String) {
        let isoFormatter = ISO8601DateFormatter()
        let timestamp = isoFormatter.string(from: Date())
        let line = "[\(timestamp)] [\(level.rawValue)] [\(agent)] \(message)"
        
        // v41.0: Push to (.utility) background worker to protect P-Core bandwidth
        Task(priority: .utility) {
            await LogWorker.shared.write(fileName: "audit.log", content: line)
            await LogWorker.shared.write(fileName: "debug.log", content: line)
        }
    }
    
    public static func logInfo(_ message: String, agent: String = "Engine") {
        logAudit(level: .info, agent: agent, message: message)
    }

    public static func logWarn(_ message: String, agent: String = "Engine") {
        logAudit(level: .warn, agent: agent, message: message)
    }

    public static func logError(_ message: String, agent: String = "Engine") {
        logAudit(level: .error, agent: agent, message: message)
    }

    public static func logSecurity(level: LogLevel, agent: String, message: String) {
        let isoFormatter = ISO8601DateFormatter()
        let timestamp = isoFormatter.string(from: Date())
        let line = "[\(timestamp)] [\(level.rawValue)] [\(agent)] \(message)"
        
        // v41.0: Push to (.utility) background worker
        Task(priority: .utility) {
            await LogWorker.shared.write(fileName: "security.log", content: line)
            await LogWorker.shared.write(fileName: "debug.log", content: line)
        }
    }
}
