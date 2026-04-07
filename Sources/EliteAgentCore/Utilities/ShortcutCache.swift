import Foundation

@MainActor
public class ShortcutCache {
    public static let shared = ShortcutCache()
    
    private var cachedList: [String] = []
    private var lastFetchDate: Date = .distantPast
    private let ttl: TimeInterval = 3600 // 1 hour
    
    private init() {}
    
    public func getShortcuts(forceRefresh: Bool = false) async -> [String] {
        if !forceRefresh, Date().timeIntervalSince(lastFetchDate) < ttl, !cachedList.isEmpty {
            return cachedList
        }
        
        do {
            let list = try await fetchFromSystem()
            self.cachedList = list
            self.lastFetchDate = Date()
            return list
        } catch {
            print("[SHORTCUTS] Cache fetch failed: \(error)")
            return cachedList // Return stale cache if fetch fails
        }
    }
    
    private func fetchFromSystem() async throws -> [String] {
        return try await withCheckedThrowingContinuation { continuation in
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/shortcuts")
            process.arguments = ["list"]
            
            let outputPipe = Pipe()
            process.standardOutput = outputPipe
            
            do {
                try process.run()
                let data = outputPipe.fileHandleForReading.readDataToEndOfFile()
                process.waitUntilExit()
                
                if let output = String(data: data, encoding: .utf8) {
                    let shortcuts = output.components(separatedBy: .newlines)
                        .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                        .filter { !$0.isEmpty }
                    continuation.resume(returning: shortcuts)
                } else {
                    continuation.resume(returning: [])
                }
            } catch {
                continuation.resume(throwing: error)
            }
        }
    }
}
