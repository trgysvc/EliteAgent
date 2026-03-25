import Foundation

public enum LogLevel: String, Sendable {
    case info = "INFO"
    case warn = "WARN"
    case error = "ERROR"
    case security = "SECURITY"
}

public struct AgentLogger: Sendable {
    public static func logAudit(level: LogLevel, agent: String, message: String) {
        writeLog(fileName: "audit.log", level: level, agent: agent, message: message)
    }
    
    public static func logSecurity(level: LogLevel, agent: String, message: String) {
        writeLog(fileName: "security.log", level: level, agent: agent, message: message)
    }
    
    private static func writeLog(fileName: String, level: LogLevel, agent: String, message: String) {
        let logPath = URL(fileURLWithPath: NSHomeDirectory())
            .appendingPathComponent(".eliteagent/logs/\(fileName)")
        
        let dir = logPath.deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        
        let isoFormatter = ISO8601DateFormatter()
        let timestamp = isoFormatter.string(from: Date())
        let logLine = "[\(timestamp)] [\(level.rawValue)] [\(agent)] \(message)\n"
        
        if let data = logLine.data(using: .utf8) {
            if FileManager.default.fileExists(atPath: logPath.path) {
                if let fileHandle = try? FileHandle(forWritingTo: logPath) {
                    fileHandle.seekToEndOfFile()
                    fileHandle.write(data)
                    fileHandle.closeFile()
                }
            } else {
                try? data.write(to: logPath)
            }
        }
    }
}
