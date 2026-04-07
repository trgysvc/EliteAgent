import Foundation
import CryptoKit
import OSLog

/// A cache manager for modular prompt construction.
/// Designed for Apple Silicon (M-series) Prompt Caching optimization.
/// Part of EliteAgent v10.0 "Titan" architecture.
public actor PromptCacheManager {
    public static let shared = PromptCacheManager()
    
    private let logger = Logger(subsystem: "com.elite.agent", category: "PromptCache")
    private var cache: [String: CachedPrompt] = [:]
    private var prefixModifier: Int = 0 // v10.0: Negative offset for shrinking
    
    private init() {
        // v10.0: Listen for adaptive action triggers from Monitor
        NotificationCenter.default.addObserver(forName: .promptCacheInefficiencyDetected, object: nil, queue: nil) { [weak self] _ in
            Task { await self?.applyAdaptiveShrink() }
        }
    }
    
    public struct CachedPrompt: Sendable {
        public let staticPart: String
        public let hash: String
        public let createdAt: Date
        
        public func resolve(dynamicPart: String) -> String {
            // Append-only to preserve the cache prefix for KV-cache reuse.
            return staticPart + "\n\n### DYNAMIC CONTEXT\n" + dynamicPart
        }
    }
    
    /// Returns a full prompt by merging cached static rules with dynamic session content.
    public func resolve(staticRules: String, dynamicContext: String) async -> String {
        let modifiedRules = applyPrefixModification(to: staticRules)
        let hash = sha256(modifiedRules)
        
        if let cached = cache[hash] {
            logger.debug("Cache HIT for prompt hash: \(hash)")
            await PromptCacheMonitor.shared.recordEvent(isHit: true)
            return cached.resolve(dynamicPart: dynamicContext)
        }
        
        // Cache MISS
        logger.info("Cache MISS for prompt hash: \(hash). Indexing...")
        await PromptCacheMonitor.shared.recordEvent(isHit: false)
        let newCached = CachedPrompt(staticPart: modifiedRules, hash: hash, createdAt: Date())
        cache[hash] = newCached
        
        return newCached.resolve(dynamicPart: dynamicContext)
    }
    
    private func applyPrefixModification(to rules: String) -> String {
        if prefixModifier == 0 { return rules }
        let targetLen = max(50, rules.count + prefixModifier)
        return String(rules.prefix(targetLen))
    }
    
    private func applyAdaptiveShrink() {
        // v10.0: Reduce prefix size to increase hit probability on next turns
        self.prefixModifier -= 20
        logger.warning("Adaptive Action: Shrinking static prefix by 20 chars (Total Modifier: \(self.prefixModifier))")
        self.clear() // Invalidate current cache to force re-indexing with new prefix
    }
    
    private func sha256(_ string: String) -> String {
        let inputData = Data(string.utf8)
        let hashed = SHA256.hash(data: inputData)
        return hashed.compactMap { String(format: "%02x", $0) }.joined()
    }
    
    public func clear() {
        cache.removeAll()
    }
}
