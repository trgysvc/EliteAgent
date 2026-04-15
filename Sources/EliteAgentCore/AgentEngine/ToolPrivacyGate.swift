import Foundation
import CryptoKit
import OSLog

public enum RiskLevel: String, Sendable {
    case low       // Read-only, stable (ls, search, web_fetch)
    case medium    // Communication, non-destructive write (send_message, calendar)
    case high      // Destructive write, exec, system-access (shell_exec, delete_file, write_file)
}

public actor ToolPrivacyGate: Sendable {
    public static let shared = ToolPrivacyGate()
    
    private let logger = Logger(subsystem: "com.elite.agent", category: "PrivacyGate")
    private var trustScores: [String: Double] = [:] // ToolName: Score (0-1)
    
    public init() {
        Task {
            await loadTrustScores()
        }
    }
    
    /// Maps a tool name to its hardcoded base risk level.
    public func baseRisk(for tool: String) -> RiskLevel {
        switch tool {
        case "ls", "read_file", "google_search", "web_search", "web_fetch", "get_system_telemetry":
            return .low
        case "send_message_via_whatsapp_or_imessage", "apple_calendar", "apple_mail":
            return .medium
        default:
            return .high
        }
    }
    
    /// Evaluates if a tool execution should be auto-approved (YOLO Mode) 
    /// or if it requires explicit user consent.
    public func evaluate(tool: String, params: [String: Any]) async -> Bool {
        let risk = baseRisk(for: tool)
        let autoApproveEnabled = UserDefaults.standard.bool(forKey: "Settings_autoApproveLowRisk")
        
        // v10.0: Dynamic Trust Score Adjustment
        let trustScore = trustScores[tool] ?? 0.8
        
        if risk == .low && autoApproveEnabled && trustScore > 0.5 {
            logAudit(tool: tool, params: params, approved: true, mode: "YOLO")
            return true
        }
        
        // High risk always requires prompt unless explicitly overridden in debug
        return false
    }
    
    /// Records tool execution for forensic audit.
    public func logAudit(tool: String, params: [String: Any], approved: Bool, mode: String) {
        let logEntry: [String: Any] = [
            "timestamp": ISO8601DateFormatter().string(from: Date()),
            "tool": tool,
            "params": params,
            "approved": approved,
            "mode": mode,
            "trust_score": trustScores[tool] ?? 0.8
        ]
        
        // Append to audit_log.json
        appendToFile(entry: logEntry)
        
        logger.info("AUDIT: [\(mode)] Tool \(tool) (Approved: \(approved))")
    }
    
    private func appendToFile(entry: [String: Any]) {
        // v13.8: UNO Pure - Shielded binary write for privacy logs
        guard let data = UNOExternalBridge.prepareExternalBlob(from: entry) else { return }
        let logURL = PathConfiguration.shared.applicationSupportURL.appendingPathComponent("audit_log.bin")
        
        if !FileManager.default.fileExists(atPath: logURL.path) {
            FileManager.default.createFile(atPath: logURL.path, contents: nil)
        }
        
        if let fileHandle = try? FileHandle(forWritingTo: logURL) {
            fileHandle.seekToEndOfFile()
            fileHandle.write(data)
            fileHandle.write("\n".data(using: .utf8)!)
            fileHandle.closeFile()
        }
    }
    
    private func loadTrustScores() {
        // v10.0: Placeholder for dynamic learning. In a real app, this would be persisted.
        self.trustScores["read_file"] = 1.0
        self.trustScores["ls"] = 1.0
        self.trustScores["shell_exec"] = 0.2
    }
}
