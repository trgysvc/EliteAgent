import Foundation

/// UsageStats holds the current metrics for display and logic.
public struct UsageStats: Codable, Sendable {
    public let sessionTokens: Int
    public let sessionCost: Double
    public let dailyTokens: Int
    public let dailyCost: Double
    public let lastResetDate: Date
}

/// UsageTracker manages both persistent (daily) and memory-only (session) usage metrics.
/// Adheres to HIG requirements for atomic, thread-safe updates.
public actor UsageTracker {
    public static let shared = UsageTracker()
    
    private let fileURL: URL
    private var dailyTokens: Int = 0
    private var dailyCost: Double = 0.0
    private var sessionTokens: Int = 0
    private var sessionCost: Double = 0.0
    private var lastResetDate: Date = Date()
    
    private init() {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let url = home.appendingPathComponent(".eliteagent/usage.plist")
        self.fileURL = url
        
        // Ensure directory exists
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        
        // v13.8: Using PropertyListDecoder for UNO Pure (No JSON Artıkları)
        if let data = try? Data(contentsOf: url),
           let decoded = try? PropertyListDecoder().decode(PersistentUsageData.self, from: data) {
            self.dailyTokens = decoded.dailyTokens
            self.dailyCost = decoded.dailyCost
            self.lastResetDate = decoded.lastResetDate
        }
        
        // Initial Rollover Check
        let now = Date()
        if !Calendar.current.isDate(lastResetDate, inSameDayAs: now) {
            self.dailyTokens = 0
            self.dailyCost = 0.0
            self.lastResetDate = now
            
            let data = PersistentUsageData(
                dailyTokens: 0,
                dailyCost: 0.0,
                lastResetDate: now
            )
            let encoder = PropertyListEncoder()
            encoder.outputFormat = .binary
            if let encoded = try? encoder.encode(data) {
                try? encoded.write(to: fileURL, options: .atomic)
            }
        }
    }
    
    /// Increments usage metrics.
    /// - Parameters:
    ///   - tokens: The number of tokens used in the current turn.
    ///   - cost: The estimated cost in USD.
    public func addUsage(tokens: Int, cost: Double) async {
        checkAndResetDailyStats()
        
        self.sessionTokens += tokens
        self.sessionCost += cost
        self.dailyTokens += tokens
        self.dailyCost += cost
        
        save()
    }
    
    /// Returns the complete set of current usage statistics.
    public func getStats() async -> UsageStats {
        checkAndResetDailyStats()
        
        return UsageStats(
            sessionTokens: sessionTokens,
            sessionCost: sessionCost,
            dailyTokens: dailyTokens,
            dailyCost: dailyCost,
            lastResetDate: lastResetDate
        )
    }
    
    /// Resets the current session metrics.
    public func resetSession() async {
        self.sessionTokens = 0
        self.sessionCost = 0.0
    }
    
    /// Checks if the day has changed and resets daily stats if needed.
    private func checkAndResetDailyStats() {
        let now = Date()
        if !Calendar.current.isDate(lastResetDate, inSameDayAs: now) {
            self.dailyTokens = 0
            self.dailyCost = 0.0
            self.lastResetDate = now
            save()
        }
    }
    
    /// Persists daily usage to the user's home directory.
    private func save() {
        let data = PersistentUsageData(
            dailyTokens: dailyTokens,
            dailyCost: dailyCost,
            lastResetDate: lastResetDate
        )
        
        let encoder = PropertyListEncoder()
        encoder.outputFormat = .binary
        guard let encoded = try? encoder.encode(data) else { return }
        try? encoded.write(to: fileURL, options: .atomic)
    }
}

/// Internal structure used for persistence.
private struct PersistentUsageData: Codable {
    var dailyTokens: Int
    var dailyCost: Double
    var lastResetDate: Date
}
