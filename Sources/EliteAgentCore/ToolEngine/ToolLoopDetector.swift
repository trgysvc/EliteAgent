import Foundation
import CryptoKit

// MARK: - ToolLoopDetector v2 (OpenClaw-Inspired Analytical Guard)
// Implements 4 independent detectors with result-hash-aware no-progress tracking.
// Thresholds aligned with OpenClaw: WARNING=10, CRITICAL=20, CIRCUIT_BREAKER=30.

public actor ToolLoopDetector {
    
    // MARK: - Types
    
    /// Severity level of a detected loop.
    public enum LoopLevel: String, Sendable {
        case warning
        case critical
    }
    
    /// Which detector triggered the alert.
    public enum LoopDetector: String, Sendable {
        case genericRepeat = "generic_repeat"
        case unknownToolRepeat = "unknown_tool_repeat"
        case knownPollNoProgress = "known_poll_no_progress"
        case pingPong = "ping_pong"
        case globalCircuitBreaker = "global_circuit_breaker"
    }
    
    /// Result of loop analysis.
    public struct LoopDetectionResult: Sendable {
        public let stuck: Bool
        public let level: LoopLevel?
        public let detector: LoopDetector?
        public let count: Int
        public let message: String?
        
        public static let clear = LoopDetectionResult(stuck: false, level: nil, detector: nil, count: 0, message: nil)
    }
    
    /// Internal record of a single tool call.
    private struct CallRecord: Sendable {
        let toolName: String
        let argsHash: String
        var resultHash: String?
        var unknownToolName: String?
        let timestamp: Date
    }
    
    // MARK: - Configuration
    
    private let warningThreshold = 10
    private let criticalThreshold = 20
    private let globalCircuitBreakerThreshold = 30
    private let unknownToolThreshold = 3
    private let historySize = 50
    
    /// Tool names treated as known polling tools.
    private static let knownPollTools: Set<String> = [
        "command_status", "shell_exec", "shell_tool"
    ]
    
    // MARK: - State
    
    private var history: [CallRecord] = []
    
    public init() {}
    
    // MARK: - Public API
    
    /// Records a tool call BEFORE execution (params only, no result yet).
    public func recordCall(toolName: String, params: [String: Any]) {
        let record = CallRecord(
            toolName: toolName,
            argsHash: Self.hashToolCall(toolName: toolName, params: params),
            resultHash: nil,
            unknownToolName: nil,
            timestamp: Date()
        )
        history.append(record)
        trimHistory()
    }
    
    /// Records the OUTCOME of a tool call after execution.
    /// This enables no-progress detection: same args + same result = no progress.
    public func recordOutcome(toolName: String, params: [String: Any], result: String, error: String? = nil) {
        let argsHash = Self.hashToolCall(toolName: toolName, params: params)
        let resultHash: String
        
        if let error = error {
            resultHash = "error:" + Self.sha256(error)
        } else {
            resultHash = Self.sha256(result)
        }
        
        // Find the most recent matching call record without a result hash
        for i in stride(from: history.count - 1, through: 0, by: -1) {
            let call = history[i]
            if call.toolName == toolName && call.argsHash == argsHash && call.resultHash == nil {
                history[i].resultHash = resultHash
                
                // Extract unknown tool name from error messages
                if let error = error {
                    history[i].unknownToolName = Self.extractUnknownToolName(from: error)
                }
                return
            }
        }
        
        // If no matching pre-recorded call found, append a complete record
        history.append(CallRecord(
            toolName: toolName,
            argsHash: argsHash,
            resultHash: resultHash,
            unknownToolName: error.flatMap { Self.extractUnknownToolName(from: $0) },
            timestamp: Date()
        ))
        trimHistory()
    }
    
    /// Analyzes the call history for repetitive patterns.
    /// Returns a LoopDetectionResult indicating whether the agent is stuck.
    public func detectLoop(currentToolName: String? = nil, currentParams: [String: Any]? = nil) -> LoopDetectionResult {
        guard history.count >= 3 else { return .clear }
        
        let currentHash: String?
        if let name = currentToolName, let params = currentParams {
            currentHash = Self.hashToolCall(toolName: name, params: params)
        } else {
            currentHash = nil
        }
        
        // 1. Unknown Tool Repeat Detector
        if let result = detectUnknownToolRepeat() {
            return result
        }
        
        // 2. Global Circuit Breaker (highest priority)
        if let result = detectGlobalCircuitBreaker() {
            return result
        }
        
        // 3. Known Poll No-Progress Detector
        if let result = detectKnownPollNoProgress() {
            return result
        }
        
        // 4. Ping-Pong Detector
        if let currentHash = currentHash, let result = detectPingPong(currentSignature: currentHash) {
            return result
        }
        
        // 5. Generic Repeat Detector
        if let result = detectGenericRepeat() {
            return result
        }
        
        return .clear
    }
    
    /// Legacy API: Returns a feedback message if a loop is detected.
    public func detectLoop() -> String? {
        let result = detectLoop(currentToolName: nil, currentParams: nil)
        return result.stuck ? result.message : nil
    }
    
    public func clear() {
        history.removeAll()
    }
    
    // MARK: - Detectors
    
    /// Detector 1: Same tool called with identical args, producing identical results.
    private func detectGenericRepeat() -> LoopDetectionResult? {
        var frequencies: [String: Int] = [:]
        
        for record in history {
            // Only count as true repeat if result hash also matches (no progress)
            let key: String
            if let resultHash = record.resultHash {
                key = "\(record.toolName):\(record.argsHash):\(resultHash)"
            } else {
                key = "\(record.toolName):\(record.argsHash)"
            }
            frequencies[key, default: 0] += 1
        }
        
        for (key, count) in frequencies {
            let toolName = key.components(separatedBy: ":").first ?? "tool"
            
            if count >= criticalThreshold {
                return LoopDetectionResult(
                    stuck: true,
                    level: .critical,
                    detector: .genericRepeat,
                    count: count,
                    message: "CRITICAL: You have called \(toolName) \(count) times with identical arguments and identical results. This is a STUCK LOOP with zero progress. STOP retrying. You MUST try a completely different approach: use a different tool, change the parameters, or write a Swift script to handle this task."
                )
            }
            
            if count >= warningThreshold {
                return LoopDetectionResult(
                    stuck: true,
                    level: .warning,
                    detector: .genericRepeat,
                    count: count,
                    message: "WARNING: You have called \(toolName) \(count) times with identical arguments. If the output is not changing, your current strategy is failing. Verify the state with a different tool before retrying."
                )
            }
        }
        
        return nil
    }
    
    /// Detector 2: Repeated calls to a tool that doesn't exist.
    private func detectUnknownToolRepeat() -> LoopDetectionResult? {
        var streak = 0
        var repeatedUnknownTool: String?
        
        for i in stride(from: history.count - 1, through: 0, by: -1) {
            let record = history[i]
            guard let unknownTool = record.unknownToolName else { break }
            
            if repeatedUnknownTool == nil {
                repeatedUnknownTool = unknownTool
                streak = 1
            } else if unknownTool == repeatedUnknownTool {
                streak += 1
            } else {
                break
            }
        }
        
        if streak >= unknownToolThreshold, let toolName = repeatedUnknownTool {
            return LoopDetectionResult(
                stuck: true,
                level: .critical,
                detector: .unknownToolRepeat,
                count: streak,
                message: "CRITICAL: You attempted to use unavailable tool '\(toolName)' \(streak) times. This tool does not exist. STOP retrying it. Check the available UBID list and use only registered tools."
            )
        }
        
        return nil
    }
    
    /// Detector 3: Polling tools (command_status, shell_exec) producing identical results.
    private func detectKnownPollNoProgress() -> LoopDetectionResult? {
        // Find streaks of known poll tools with no-progress results
        var pollStreaks: [String: (count: Int, lastResult: String?)] = [:]
        
        for record in history {
            guard Self.knownPollTools.contains(record.toolName) else { continue }
            let key = "\(record.toolName):\(record.argsHash)"
            
            if let existing = pollStreaks[key] {
                // Check if result is the same (no progress)
                if record.resultHash == existing.lastResult && record.resultHash != nil {
                    pollStreaks[key] = (existing.count + 1, record.resultHash)
                } else {
                    // Progress was made — reset
                    pollStreaks[key] = (1, record.resultHash)
                }
            } else {
                pollStreaks[key] = (1, record.resultHash)
            }
        }
        
        for (key, streak) in pollStreaks {
            let toolName = key.components(separatedBy: ":").first ?? "poll_tool"
            
            if streak.count >= criticalThreshold {
                return LoopDetectionResult(
                    stuck: true,
                    level: .critical,
                    detector: .knownPollNoProgress,
                    count: streak.count,
                    message: "CRITICAL: Called \(toolName) \(streak.count) times with identical arguments and NO progress in output. This is a stuck polling loop. Session blocked to prevent resource waste. Either increase wait time between checks, or report the task as failed."
                )
            }
            
            if streak.count >= warningThreshold {
                return LoopDetectionResult(
                    stuck: true,
                    level: .warning,
                    detector: .knownPollNoProgress,
                    count: streak.count,
                    message: "WARNING: You have polled \(toolName) \(streak.count) times with identical results. The process appears stuck. Either increase the wait interval, try a different diagnostic command, or report the task as failed."
                )
            }
        }
        
        return nil
    }
    
    /// Detector 4: A→B→A→B alternating pattern (ping-pong).
    private func detectPingPong(currentSignature: String) -> LoopDetectionResult? {
        guard history.count >= 4 else { return nil }
        
        let last = history[history.count - 1]
        
        // Find the most recent call with a different signature
        var otherSignature: String?
        var otherToolName: String?
        for i in stride(from: history.count - 2, through: 0, by: -1) {
            let call = history[i]
            if call.argsHash != last.argsHash {
                otherSignature = call.argsHash
                otherToolName = call.toolName
                break
            }
        }
        
        guard let otherSig = otherSignature else { return nil }
        
        // Count alternating tail
        var alternatingCount = 0
        for i in stride(from: history.count - 1, through: 0, by: -1) {
            let call = history[i]
            let expected = alternatingCount % 2 == 0 ? last.argsHash : otherSig
            if call.argsHash != expected { break }
            alternatingCount += 1
        }
        
        guard alternatingCount >= 4 else { return nil }
        
        // Check if results are also stuck (no-progress evidence)
        let tailStart = max(0, history.count - alternatingCount)
        var firstHashA: String?
        var firstHashB: String?
        var noProgress = true
        
        for i in tailStart..<history.count {
            let call = history[i]
            guard let rh = call.resultHash else {
                noProgress = false
                break
            }
            if call.argsHash == last.argsHash {
                if firstHashA == nil { firstHashA = rh }
                else if firstHashA != rh { noProgress = false; break }
            } else {
                if firstHashB == nil { firstHashB = rh }
                else if firstHashB != rh { noProgress = false; break }
            }
        }
        
        let toolDescription = "\(last.toolName) ↔ \(otherToolName ?? "other")"
        
        if alternatingCount >= criticalThreshold && noProgress {
            return LoopDetectionResult(
                stuck: true,
                level: .critical,
                detector: .pingPong,
                count: alternatingCount,
                message: "CRITICAL: You are alternating between \(toolDescription) (\(alternatingCount) consecutive calls) with no progress. This is a stuck ping-pong loop. STOP and try a completely different approach."
            )
        }
        
        if alternatingCount >= warningThreshold {
            return LoopDetectionResult(
                stuck: true,
                level: .warning,
                detector: .pingPong,
                count: alternatingCount,
                message: "WARNING: Alternating tool-call pattern detected between \(toolDescription) (\(alternatingCount) calls). This looks like a ping-pong loop. Stop retrying and report the task as failed or try a different strategy."
            )
        }
        
        return nil
    }
    
    /// Global circuit breaker: any tool repeated too many times regardless of results.
    private func detectGlobalCircuitBreaker() -> LoopDetectionResult? {
        var argFrequencies: [String: Int] = [:]
        
        for record in history {
            let key = "\(record.toolName):\(record.argsHash)"
            argFrequencies[key, default: 0] += 1
        }
        
        for (key, count) in argFrequencies {
            if count >= globalCircuitBreakerThreshold {
                let toolName = key.components(separatedBy: ":").first ?? "tool"
                return LoopDetectionResult(
                    stuck: true,
                    level: .critical,
                    detector: .globalCircuitBreaker,
                    count: count,
                    message: "CRITICAL: \(toolName) has been called \(count) times with identical arguments. Global circuit breaker triggered. Session execution blocked to prevent runaway loops. The agent must adopt a fundamentally different strategy."
                )
            }
        }
        
        return nil
    }
    
    // MARK: - Hashing Utilities
    
    /// Creates a deterministic hash for a tool call (name + sorted params).
    private static func hashToolCall(toolName: String, params: [String: Any]) -> String {
        let sortedKeys = params.keys.sorted()
        let paramString = sortedKeys.map { "\($0):\(params[$0] ?? "")" }.joined(separator: "|")
        let combined = "\(toolName):\(paramString)"
        return sha256(combined)
    }
    
    /// SHA-256 hash of a string.
    private static func sha256(_ input: String) -> String {
        let hash = SHA256.hash(data: Data(input.utf8))
        return hash.compactMap { String(format: "%02x", $0) }.joined()
    }
    
    /// Extracts an unknown tool name from error messages.
    private static func extractUnknownToolName(from error: String) -> String? {
        let patterns = [
            "Tool not found.*?Identifier: (\\w+)",
            "unknown tool.*?[\"']?(\\w+)[\"']?",
            "tool.*?(\\w+).*?not found"
        ]
        
        for pattern in patterns {
            if let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) {
                let nsError = error as NSString
                if let match = regex.firstMatch(in: error, range: NSRange(location: 0, length: nsError.length)),
                   match.numberOfRanges > 1 {
                    return nsError.substring(with: match.range(at: 1)).lowercased()
                }
            }
        }
        
        return nil
    }
    
    // MARK: - Statistics
    
    /// Returns diagnostic statistics for monitoring.
    public func getStats() -> (totalCalls: Int, uniquePatterns: Int, mostFrequent: (toolName: String, count: Int)?) {
        var patterns: [String: (toolName: String, count: Int)] = [:]
        
        for call in history {
            let key = call.argsHash
            if let existing = patterns[key] {
                patterns[key] = (existing.toolName, existing.count + 1)
            } else {
                patterns[key] = (call.toolName, 1)
            }
        }
        
        let mostFrequent = patterns.values.max(by: { $0.count < $1.count })
        
        return (
            totalCalls: history.count,
            uniquePatterns: patterns.count,
            mostFrequent: mostFrequent
        )
    }
    
    // MARK: - Private
    
    private func trimHistory() {
        if history.count > historySize {
            history.removeFirst(history.count - historySize)
        }
    }
}
