import Foundation
import Cocoa
import ApplicationServices

public actor BrowserAgent: AgentProtocol {
    public let agentID: AgentID = .browserAgent
    public private(set) var status: AgentStatus = .idle
    public let preferredProvider: ProviderID = .none
    public let fallbackProviders: [ProviderID] = []
    
    private let bus: SignalBus
    
    public init(bus: SignalBus) {
        self.bus = bus
    }
    
    private func navigateAXUIElement(url: URL) -> Bool {
        guard let safariApp = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.Safari").first else { return false }
        let appElement = AXUIElementCreateApplication(safariApp.processIdentifier)
        
        var windows: AnyObject?
        AXUIElementCopyAttributeValue(appElement, kAXWindowsAttribute as CFString, &windows)
        guard let windowArray = windows as? [AXUIElement], let frontWindow = windowArray.first else { return false }
        
        // v7.0: Native Address Bar Discovery
        guard let addressBar = findElement(role: kAXTextFieldRole, identifier: "WEB_BROWSER_ADDRESS_AND_SEARCH_FIELD", in: frontWindow) else { return false }
        
        AXUIElementSetAttributeValue(addressBar, kAXValueAttribute as CFString, url.absoluteString as CFTypeRef)
        AXUIElementPerformAction(addressBar, kAXConfirmAction as CFString)
        return true
    }
    
    private func findElement(role: String? = nil, identifier: String? = nil, title: String? = nil, in element: AXUIElement) -> AXUIElement? {
        var currentRole: AnyObject?
        AXUIElementCopyAttributeValue(element, kAXRoleAttribute as CFString, &currentRole)
        
        var currentID: AnyObject?
        AXUIElementCopyAttributeValue(element, kAXIdentifierAttribute as CFString, &currentID)
        
        var currentTitle: AnyObject?
        AXUIElementCopyAttributeValue(element, kAXTitleAttribute as CFString, &currentTitle)
        
        let roleMatch = role == nil || (currentRole as? String) == role
        let idMatch = identifier == nil || (currentID as? String)?.contains(identifier!) == true
        let titleMatch = title == nil || (currentTitle as? String) == title
        
        if roleMatch && idMatch && titleMatch {
            return element
        }
        
        var children: AnyObject?
        AXUIElementCopyAttributeValue(element, kAXChildrenAttribute as CFString, &children)
        if let childrenArray = children as? [AXUIElement] {
            for child in childrenArray {
                if let found = findElement(role: role, identifier: identifier, title: title, in: child) {
                    return found
                }
            }
        }
        return nil
    }
    
    public func receive(_ signal: Signal) async throws {
        if signal.name == "BROWSER_ACTION" {
            self.status = .working
            
            guard let dict = UNOExternalBridge.resolveDictionary(from: signal.payload),
                  let type = dict["type"] as? String else {
                self.status = .idle
                return
            }
            
            do {
                var currentURLStr = ""
                if type == "navigate", let targetUrl = dict["url"] as? String {
                    currentURLStr = targetUrl
                } else if type != "list_tabs" && type != "switch_tab" {
                    currentURLStr = try SafariJSBridge.getCurrentURL()
                }
                
                // Security Check for domain-restricted actions
                if !currentURLStr.isEmpty {
                    let vaultConfig = await VaultManager.shared?.config
                    let allowedDomains = vaultConfig?.browser?.allowedDomains ?? ["*"]
                    
                    if let host = URL(string: currentURLStr)?.host, !allowedDomains.contains(where: { host.hasSuffix($0) || $0 == "*" }) {
                        AgentLogger.logAudit(level: .security, agent: "BrowserAgent", message: "BLOCKED_DOMAIN: \(currentURLStr)")
                        try await bus.dispatch(Signal(source: .browserAgent, target: signal.source, name: "BROWSER_ERROR", priority: .high, payload: "DOMAIN_VIOLATION".data(using: .utf8)!, secretKey: bus.sharedSecret))
                        self.status = .idle
                        return
                    }
                }
                
                var resultText = ""
                
                switch type {
                case "navigate":
                    guard let urlStr = dict["url"] as? String, let url = URL(string: urlStr) else { break }
                    let success = navigateAXUIElement(url: url)
                    resultText = success ? "Navigated to \(urlStr) via AX" : "AX Navigation Failed"
                    
                case "read":
                    resultText = try SafariJSBridge.evaluate("document.body.innerText")
                    
                case "fill":
                    guard let fields = dict["fields"] as? [String: String] else { break }
                    // v7.0: Native AX Form Fill (No JS injection unless AX fails)
                    if let safari = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.Safari").first {
                        let app = AXUIElementCreateApplication(safari.processIdentifier)
                        for (id, val) in fields {
                            if let el = findElement(identifier: id, in: app) {
                                AXUIElementSetAttributeValue(el, kAXValueAttribute as CFString, val as CFTypeRef)
                                resultText += "Filled \(id) via AX. "
                            } else {
                                // Fallback to JS
                                let script = "var el = document.getElementById('\(id)') || document.querySelector('[name=\"\(id)\"]'); if (el) el.value = '\(val)';"
                                _ = try SafariJSBridge.evaluate(script)
                                resultText += "Filled \(id) via JS. "
                            }
                        }
                    }
                    
                case "list_tabs":
                    resultText = try SafariJSBridge.listTabs()
                    
                case "switch_tab":
                    guard let win = dict["window"] as? Int, let tab = dict["tab"] as? Int else { break }
                    try SafariJSBridge.switchToTab(windowIndex: win, tabIndex: tab)
                    resultText = "Switched to Window \(win), Tab \(tab)"
                    
                case "query":
                    guard let selector = dict["selector"] as? String else { break }
                    let escaped = selector.replacingOccurrences(of: "'", with: "\\'")
                    resultText = try SafariJSBridge.evaluate("var el = document.querySelector('\(escaped)'); el ? el.outerHTML : ''")
                    
                default:
                    break
                }
                
                AgentLogger.logAudit(level: .info, agent: "BrowserAgent", message: "SUCCESS: \(type)")
                try await bus.dispatch(Signal(source: .browserAgent, target: signal.source, name: "BROWSER_RESULT", priority: .high, payload: resultText.data(using: .utf8)!, secretKey: bus.sharedSecret))
                
            } catch {
                AgentLogger.logAudit(level: .error, agent: "BrowserAgent", message: "ERROR: \(error.localizedDescription)")
                try await bus.dispatch(Signal(source: .browserAgent, target: signal.source, name: "BROWSER_ERROR", priority: .high, payload: error.localizedDescription.data(using: .utf8)!, secretKey: bus.sharedSecret))
            }
            
            self.status = .idle
        }
    }
    
    public func healthReport() -> AgentHealth {
        return AgentHealth(isHealthy: true, statusMessage: "OK")
    }
}
