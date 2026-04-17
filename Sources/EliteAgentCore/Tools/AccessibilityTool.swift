import Foundation
import AppKit
import OSLog

/// A tool for Accessibility-based app interaction (v10.0 'AX').
/// Uses AXUIElement for clicking, typing, and reading UI state.
public struct AccessibilityTool: AgentTool {
    public let name = "apple_accessibility"
    public let summary = "Direct AXUIElement interaction with native apps."
    public let description = "Interacts with macOS applications using the Accessibility API."
    public let ubid: Int128 = 24 // Token '9' in Qwen 2.5
    
    private let logger = Logger(subsystem: "com.elite.agent", category: "AX")
    
    public init() {}
    
    public func execute(params: [String: AnyCodable], session: Session) async throws(AgentToolError) -> String {
        guard let appName = params["target_app"]?.value as? String else {
            throw AgentToolError.missingParameter("target_app")
        }
        
        // 1. Permission Check
        if !AXIsProcessTrusted() {
            logger.warning("AX not trusted. Falling back to AppleScript.")
            do {
                return try await executeAppleScriptFallback(params)
            } catch {
                throw AgentToolError.executionError(error.localizedDescription)
            }
        }
        
        // 2. Resolve App
        let app = NSRunningApplication.runningApplications(withBundleIdentifier: appName).first ??
                  NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple." + appName).first
        
        guard let validApp = app else {
            throw AgentToolError.executionError("App '\(appName)' not found.")
        }
        
        let appElement = AXUIElementCreateApplication(validApp.processIdentifier)
        
        // 3. Action Logic (v10.0 Prototype: Click by name)
        if let clickTarget = params["click"]?.value as? String {
            return try await performClick(on: clickTarget, in: appElement)
        }
        
        return "App '\(appName)' found. No specific action performed."
    }
    
    private func performClick(on name: String, in element: AXUIElement) async throws(AgentToolError) -> String {
        do {
            if let target = try await findElement(named: name, in: element) {
                let action: CFString = kAXPressAction as CFString
                AXUIElementPerformAction(target, action)
                return "Successfully clicked '\(name)'"
            }
            return "Element '\(name)' not found."
        } catch {
            throw error
        }
    }
    
    private func findElement(named name: String, in element: AXUIElement) async throws(AgentToolError) -> AXUIElement? {
        // Simple recursive search (v10.0 Prototype)
        // In a real implementation, this would be more robust
        return nil // Placeholder
    }
    
    private func executeAppleScriptFallback(_ params: [String: AnyCodable]) async throws(AgentToolError) -> String {
        guard let app = params["target_app"]?.value as? String else { throw AgentToolError.missingParameter("target_app") }
        let script = "tell application \"\(app)\" to activate"
        
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        proc.arguments = ["-e", script]
        
        do {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                proc.terminationHandler = { _ in continuation.resume() }
                do {
                    try proc.run()
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        } catch {
            throw AgentToolError.executionError("AppleScript fallback failed: \(error.localizedDescription)")
        }
        
        return "DegradedMode: Activated \(app) via AppleScript fallback."
    }
}
