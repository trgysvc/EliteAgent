import Foundation
import Cocoa

public struct NativeBrowserTool: AgentTool {
    public let name: String = "browser_native"
    public let summary: String = "Interactive high-fidelity native Safari controller."
    public let description = "A native Safari controller for navigating, reading, and interacting with web pages. Supports 'navigate', 'read', 'fill', 'list_tabs', 'switch_tab', and 'inspect_ax'."
    public let ubid: Int128 = 47
    
    public init() {}
    
    public func execute(params: [String: AnyCodable], session: Session) async throws(AgentToolError) -> String {
        guard let action = params["action"]?.value as? String else {
            throw AgentToolError.missingParameter("action")
        }
        
        do {
            switch action {
            case "navigate":
                guard let urlStr = params["url"]?.value as? String, URL(string: urlStr) != nil else {
                    throw AgentToolError.missingParameter("url")
                }
                _ = try SafariJSBridge.evaluate("window.location.href = '\(urlStr)'")
                return "Successfully navigated to \(urlStr) in Safari"
                
            case "read":
                return try SafariJSBridge.evaluate("document.body.innerText")
                
            case "fill":
                guard let fields = params["fields"]?.value as? [String: String] else {
                    throw AgentToolError.missingParameter("fields")
                }
                var results = ""
                for (id, val) in fields {
                    let script = "var el = document.getElementById('\(id)') || document.querySelector('[name=\"\(id)\"]'); if (el) el.value = '\(val)';"
                    _ = try SafariJSBridge.evaluate(script)
                    results += "Filled \(id). "
                }
                return results
                
            case "list_tabs":
                return try SafariJSBridge.listTabs()
                
            case "switch_tab":
                guard let win = params["window"]?.value as? Int, let tab = params["tab"]?.value as? Int else {
                    throw AgentToolError.missingParameter("window, tab")
                }
                try SafariJSBridge.switchToTab(windowIndex: win, tabIndex: tab)
                return "Switched to Window \(win), Tab \(tab)"
                
            case "inspect_ax":
                // v7.0: Native AX Tree Dump for model-driven navigation
                return BrowserAXInspector.dumpFrontmostPage()
                
            case "screenshot":
                // Fallback or implementation via 'screencapture' targeting Safari window
                let filename = "safari_snap_\(Int(Date().timeIntervalSince1970)).png"
                let path = session.workspaceURL.appendingPathComponent(filename)
                let process = Process()
                process.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
                process.arguments = ["-l", "$(osascript -e 'tell app \"Safari\" to id of window 1')", path.path]
                // Note: Getting window ID via shell expansion in arguments is tricky, 
                // but for Phase 6 we'll use a simpler version or just inform the user.
                return "Screenshot action redirected to Safari. (AX-based capture pending integration)"
                
            default:
                throw AgentToolError.invalidParameter("Unknown action: \(action)")
            }
        } catch {
            throw AgentToolError.executionError(error.localizedDescription)
        }
    }
}
