import Foundation

/// Runtime configuration for v10.0 Token Guards.
/// Implements precedence: CLI > Env > UserDefaults > Default.
public struct TokenGuardConfig: Sendable {
    public static let shared = TokenGuardConfig.resolve()
    
    public let isTraceEnabled: Bool
    public let isBriefMode: Bool
    public let cacheHitThreshold: Double
    public let dreamSavingsRatio: Double
    public let isUpdateBaselineMode: Bool
    
    private init(
        isTraceEnabled: Bool,
        isBriefMode: Bool,
        cacheHitThreshold: Double,
        dreamSavingsRatio: Double,
        isUpdateBaselineMode: Bool
    ) {
        self.isTraceEnabled = isTraceEnabled
        self.isBriefMode = isBriefMode
        self.cacheHitThreshold = cacheHitThreshold
        self.dreamSavingsRatio = dreamSavingsRatio
        self.isUpdateBaselineMode = isUpdateBaselineMode
    }
    
    public static func resolve() -> TokenGuardConfig {
        let args = CommandLine.arguments
        let env = ProcessInfo.processInfo.environment
        
        // 1. Trace Flag
        let trace = args.contains("--token-trace") || (env["ELITE_TOKEN_TRACE"] == "1")
        
        // 2. Brief Mode
        let brief = args.contains("--brief") || 
                    (env["ELITE_BRIEF_MODE"] == "1") || 
                    UserDefaults.standard.bool(forKey: "briefModeEnabled")
        
        // 3. Cache Threshold
        let thresholdStr = env["ELITE_CACHE_THRESHOLD"] ?? "0.60"
        let threshold = Double(thresholdStr) ?? 0.60
        
        // 4. Update Baseline
        let updateBaseline = args.contains("--update-baseline")
        
        return TokenGuardConfig(
            isTraceEnabled: trace,
            isBriefMode: brief,
            cacheHitThreshold: threshold,
            dreamSavingsRatio: 0.25,
            isUpdateBaselineMode: updateBaseline
        )
    }
}
