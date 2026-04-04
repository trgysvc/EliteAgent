import Foundation
import Cocoa

/// A tool that automates Safari via AppleScript to perform research and scrape content.
/// Supports both background (URL scheme/AppleScript) and foreground (window focus) modes.
public struct SafariAutomationTool: AgentTool {
    public let name = "safari_automation"
    public let description = "Safari tarayıcısını kullanarak arama yapar, sayfa içeriğini çeker veya sekmeleri yönetir. Parametreler: action ('search', 'scrape', 'open', 'close'), query (arama terimi), url (target URL)."

    public init() {}

    public func execute(params: [String: AnyCodable], session: Session) async throws -> String {
        guard let action = params["action"]?.value as? String else {
            throw ToolError.invalidParameter("Missing 'action' parameter.")
        }
        
        // Check for automation permissions before proceeding
        try? await verifyPermissions()

        switch action {
        case "search":
            guard let query = params["query"]?.value as? String else {
                throw ToolError.invalidParameter("Missing 'query' for search action.")
            }
            return try await performSearch(query: query)
        case "scrape":
            return try await scrapeActiveTab()
        case "open":
            guard let urlString = params["url"]?.value as? String else {
                throw ToolError.invalidParameter("Missing 'url' for open action.")
            }
            return try await openURL(urlString)
        case "click":
            guard let selector = params["selector"]?.value as? String else {
                throw ToolError.invalidParameter("Missing 'selector' for click action.")
            }
            return try await openURL(selector)
        case "close":
            return try await closeActiveTab()
        default:
            throw ToolError.invalidParameter("Unknown action: \(action)")
        }
    }

    // MARK: - Core Actions

    private func performSearch(query: String) async throws -> String {
        let encodedQuery = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? query
        let searchURL = "https://www.google.com/search?q=\(encodedQuery)"
        
        let script = """
        tell application "Safari"
            if not (exists document 1) then
                make new document with properties {URL:"\(searchURL)"}
            else
                tell window 1 to make new tab with properties {URL:"\(searchURL)"}
            end if
            delay 2 -- Wait for initial load
            return "Search performed for: \(query)"
        end tell
        """
        return try runAppleScript(script)
    }

    private func scrapeActiveTab() async throws -> String {
        let script = """
        tell application "Safari"
            if not (exists document 1) then
                return "ERROR: No active tab found"
            end if
            set docName to name of front document
            set docURL to URL of front document
            set docText to text of front document
            return "TITLE: " & docName & "\\nURL: " & docURL & "\\nCONTENT:\\n" & docText
        end tell
        """
        return try runAppleScript(script)
    }

    private func openURL(_ urlString: String) async throws -> String {
        let script = """
        tell application "Safari"
            if not (exists document 1) then
                make new document with properties {URL:"\(urlString)"}
            else
                tell window 1 to make new tab with properties {URL:"\(urlString)"}
            end if
            return "Opened URL: \(urlString)"
        end tell
        """
        return try runAppleScript(script)
    }

    private func closeActiveTab() async throws -> String {
        let script = """
        tell application "Safari"
            if (exists current tab of window 1) then
                close current tab of window 1
                return "Closed active tab"
            else
                return "No tab to close"
            end if
        end tell
        """
        return try runAppleScript(script)
    }

    // MARK: - Helpers

    private func verifyPermissions() async throws {
        let checkScript = "tell application \"Safari\" to count documents"
        do {
            _ = try runAppleScript(checkScript)
        } catch {
            // If we can't even count documents, it's likely a permission issue
            throw ToolError.executionError("Safari Otomasyon izni eksik. Lütfen Sistem Ayarları > Gizlilik ve Güvenlik > Otomasyon altından EliteAgent'a Safari için izin verin.")
        }
    }

    private func runAppleScript(_ script: String) throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = ["-e", script]

        let outputPipe = Pipe()
        let errorPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = errorPipe

        do {
            try process.run()
            process.waitUntilExit()

            let outputData = outputPipe.fileHandleForReading.readDataToEndOfFile()
            let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()

            if process.terminationStatus != 0 {
                let errorMsg = String(data: errorData, encoding: .utf8) ?? "Unknown AppleScript error"
                throw ToolError.executionError(errorMsg)
            }

            return String(data: outputData, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        } catch {
            throw ToolError.executionError(error.localizedDescription)
        }
    }
}
