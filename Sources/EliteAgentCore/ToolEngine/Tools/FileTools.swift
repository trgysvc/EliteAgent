import Foundation

public enum FileAgentToolError: Error, Sendable, CustomStringConvertible {
    case permissionDenied(path: String)
    case notFound(path: String)
    case writeFailed(Error)
    
    public var description: String {
        switch self {
        case .permissionDenied(let p): return "Access Denied: You cannot read/write outside allowed boundaries. (\(p))"
        case .notFound(let p): return "File not found: \(p)"
        case .writeFailed(let e): return "Atomic write failed: \(e.localizedDescription)"
        }
    }
}

public struct FileTools: Sendable {
    public let allowedPaths: [String]
    
    public init(allowedPaths: [String] = ["/Users/Shared/EliteAgent"]) {
        self.allowedPaths = allowedPaths
    }
    
    private func validateAndResolve(path: String) throws -> URL {
        let url = URL(fileURLWithPath: path).standardizedFileURL
        let pathString = url.path
        
        let isAllowed = allowedPaths.contains { pathString.hasPrefix($0) }
        guard isAllowed else {
            throw FileAgentToolError.permissionDenied(path: pathString)
        }
        return url
    }
    
    public func readFile(path: String) throws -> String {
        let url = try validateAndResolve(path: path)
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw FileAgentToolError.notFound(path: url.path)
        }
        return try String(contentsOf: url, encoding: .utf8)
    }
    
    public func writeFileSyncAtomic(path: String, content: String) throws {
        let url = try validateAndResolve(path: path)
        let parentURL = url.deletingLastPathComponent()
        if !FileManager.default.fileExists(atPath: parentURL.path) {
            try FileManager.default.createDirectory(at: parentURL, withIntermediateDirectories: true, attributes: nil)
        }
        
        let tempURL = parentURL.appendingPathComponent(".\(UUID().uuidString).tmp")
        
        do {
            try content.write(to: tempURL, atomically: true, encoding: .utf8)
            let fileManager = FileManager.default
            
            if fileManager.fileExists(atPath: url.path) {
                _ = try fileManager.replaceItemAt(url, withItemAt: tempURL)
            } else {
                try fileManager.moveItem(at: tempURL, to: url)
            }
        } catch {
            throw FileAgentToolError.writeFailed(error)
        }
    }
}
