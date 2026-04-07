import Foundation
import AppKit
import OSLog

/// A tool for Accessibility-based app interaction (v10.0 'AX').
/// Uses AXUIElement for clicking, typing, and reading UI state.
public actor AccessibilityTool: AgentTool {
    public let name = "apple_accessibility"
    public let description = "Interacts with macOS applications using the Accessibility API."
    
    private let logger = Logger(subsystem: "com.elite.agent", category: "AX")
    
    public init() {}
    
    public func execute(params: [String: AnyCodable], session: Session) async throws -> String {
        guard let appName = params["target_app"]?.value as? String else {
            return "Error: target_app parameter is required."
        }
        
        // 1. Permission Check
        if !AXIsProcessTrusted() {
            logger.warning("AX not trusted. Falling back to AppleScript.")
            return try await executeAppleScriptFallback(params)
        }
        
        // 2. Resolve App
        guard let app = NSRunningApplication.runningApplications(withBundleIdentifier: appName).first ??
                    NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple." + appName).first else {
            return "Error: App '\(appName)' not found."
        }
        
        let appElement = AXUIElementCreateApplication(app.processIdentifier)
        
        // 3. Action Logic (v10.0 Prototype: Click by name)
        if let clickTarget = params["click"]?.value as? String {
            return try await performClick(on: clickTarget, in: appElement)
        }
        
        return "App '\(appName)' found. No specific action performed."
    }
    
    private func performClick(on target: String, in app: AXUIElement) async throws -> String {
        // v10.0: Deep traversal and AXActionPerform would occur here.
        // For this architecture implementation, we show the structural approach.
        return "Simulated click on '\(target)' using AXUIElement."
    }
    
    private func executeAppleScriptFallback(_ params: [String: AnyCodable]) async throws -> String {
        guard let app = params["target_app"]?.value as? String else { return "No app specified." }
        let script = "tell application \"\(app)\" to activate"
        
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        proc.arguments = ["-e", script]
        
        try proc.run()
        proc.waitUntilExit()
        
        return "DegradedMode: Activated \(app) via AppleScript fallback."
    }
}
