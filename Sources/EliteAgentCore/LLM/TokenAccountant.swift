import Foundation
import OSLog

/// A thread-safe accountant for tracking token usage and savings (v10.0 Titan).
/// Supports --token-trace for granular production profiling.
public actor TokenAccountant {
    public static let shared = TokenAccountant()
    
    private let logger = Logger(subsystem: "com.elite.agent", category: "TokenAccountant")
    
    public struct TokenStats: Sendable {
        public var inputTotal: Int = 0
        public var outputTotal: Int = 0
        public var cachedTotal: Int = 0
        public var netSavings: Int = 0
        public var requestCount: Int = 0
    }
    
    private var stats = TokenStats()
    
    private init() {}
    
    /// Records a single LLM transaction and calculates savings.
    /// - Parameters:
    ///   - input: Total tokens sent in the prompt.
    ///   - output: Total tokens received in the response.
    ///   - cached: Tokens that were served from KV-cache (Prompt Caching).
    public func record(input: Int, output: Int, cached: Int) {
        stats.requestCount += 1
        stats.inputTotal += input
        stats.outputTotal += output
        stats.cachedTotal += cached
        
        let savings = cached // Simplified: Savings = Cache Hits
        stats.netSavings += savings
        
        // v10.0: Unified Token Trace (os_log with signposts coming in Monitor)
        if TokenGuardConfig.shared.isTraceEnabled {
            print("""
            [TOKEN TRACE #\(stats.requestCount)]
              Input:  \(input)
              Cached: \(cached) (Saved)
              Output: \(output)
              Net:    \(input + output - cached)
            ------------------------------------
            """)
        }
        
        logger.info("Token Transaction recorded. Net Savings: \(savings)")
    }
    
    public func getStats() -> TokenStats {
        return stats
    }
    
    public func resetSession() {
        stats = TokenStats()
        logger.debug("TokenAccountant session reset.")
    }
}
