import Foundation
import OSLog

/// A singleton actor responsible for tracking and enforcing token and cost budgets.
/// Aligned with EliteAgent v10.0 "Titan" architecture for energy-aware intelligence.
public actor TokenBudgetActor {
    public static let shared = TokenBudgetActor()
    
    private let logger = Logger(subsystem: "com.elite.agent", category: "TokenBudget")
    
    public struct BudgetMetrics: Sendable {
        public var dailyTokenUsage: Int = 0
        public var dailyCostUSD: Decimal = 0
        public var sessionTokenUsage: Int = 0
        public var sessionCostUSD: Decimal = 0
        public var maxSessionTokens: Int = 8192 // ULTRAPLAN limit
        public var dailyLimitUSD: Decimal = 5.0
    }
    
    private var metrics = BudgetMetrics()
    private var lastResetDate: Date = Date()
    
    private init() {
        self.metrics.dailyTokenUsage = UserDefaults.standard.integer(forKey: "TB_dailyTokenUsage")
        let costDouble = UserDefaults.standard.double(forKey: "TB_dailyCostUSD")
        self.metrics.dailyCostUSD = Decimal(costDouble)
        self.lastResetDate = UserDefaults.standard.object(forKey: "TB_lastResetDate") as? Date ?? Date()
    }
    
    /// Records usage from a completed LLM request.
    public func recordUsage(tokens: Int, cost: Decimal) {
        checkDailyReset()
        
        self.metrics.dailyTokenUsage += tokens
        self.metrics.dailyCostUSD += cost
        self.metrics.sessionTokenUsage += tokens
        self.metrics.sessionCostUSD += cost
        
        self.saveMetrics()
        
        logger.info("Usage Recorded: +\(tokens) tokens ($\(cost)). Daily Total: $\(self.metrics.dailyCostUSD)")
    }
    
    /// Resets the session-specific counters.
    public func startNewSession(maxTokens: Int = 8192) {
        self.metrics.sessionTokenUsage = 0
        self.metrics.sessionCostUSD = 0
        self.metrics.maxSessionTokens = maxTokens
        logger.debug("New session started with token limit: \(maxTokens)")
    }
    
    /// Checks if the current request is within budget and energy limits.
    /// - Returns: True if allowed, False if throttled or over budget.
    public func requestApproval(estimatedTokens: Int) -> Bool {
        checkDailyReset()
        
        // 1. Daily Cost Limit
        if self.metrics.dailyCostUSD >= self.metrics.dailyLimitUSD {
            logger.warning("Daily budget exceeded: $\(self.metrics.dailyCostUSD) >= $\(self.metrics.dailyLimitUSD)")
            return false
        }
        
        // 2. Session Token Limit (ULTRAPLAN Guard)
        if self.metrics.sessionTokenUsage + estimatedTokens > self.metrics.maxSessionTokens {
            logger.warning("Session token limit reached: \(self.metrics.sessionTokenUsage) + \(estimatedTokens) > \(self.metrics.maxSessionTokens)")
            return false
        }
        
        // 3. Energy Awareness (Apple Silicon Native)
        let thermalState = ProcessInfo.processInfo.thermalState
        if thermalState == .critical {
            logger.error("Thermal state CRITICAL. Throttling all non-essential LLM requests.")
            return false
        }
        
        return true
    }
    
    public func getMetrics() -> BudgetMetrics {
        return self.metrics
    }
    
    // MARK: - Private Persistence
    
    private func checkDailyReset() {
        let now = Date()
        if !Calendar.current.isDate(now, inSameDayAs: lastResetDate) {
            self.metrics.dailyTokenUsage = 0
            self.metrics.dailyCostUSD = 0
            self.lastResetDate = now
            self.saveMetrics()
            logger.info("Daily token budget reset for new day.")
        }
    }
    
    private func saveMetrics() {
        // v10.0: Persist daily totals to UserDefaults for session survival
        UserDefaults.standard.set(self.metrics.dailyTokenUsage, forKey: "TB_dailyTokenUsage")
        let doubleValue = (self.metrics.dailyCostUSD as NSDecimalNumber).doubleValue
        UserDefaults.standard.set(doubleValue, forKey: "TB_dailyCostUSD")
        UserDefaults.standard.set(self.lastResetDate, forKey: "TB_lastResetDate")
    }
    
    // loadMetrics() logic moved to init() for Swift 6 conformance.
}
