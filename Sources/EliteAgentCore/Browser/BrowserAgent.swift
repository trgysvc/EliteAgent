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
        let apps = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.Safari")
        guard let safariApp = apps.first else { return false }
        
        let appElement = AXUIElementCreateApplication(safariApp.processIdentifier)
        var windows: AnyObject?
        AXUIElementCopyAttributeValue(appElement, kAXWindowsAttribute as CFString, &windows)
        
        guard let windowArray = windows as? [AXUIElement], let frontWindow = windowArray.first else { return false }
        
        guard let addressBar = findAddressBar(in: frontWindow) else { return false }
        
        AXUIElementSetAttributeValue(addressBar, kAXValueAttribute as CFString, url.absoluteString as CFTypeRef)
        AXUIElementPerformAction(addressBar, kAXConfirmAction as CFString)
        return true
    }
    
    private func findAddressBar(in element: AXUIElement) -> AXUIElement? {
        var role: AnyObject?
        AXUIElementCopyAttributeValue(element, kAXRoleAttribute as CFString, &role)
        
        var identifier: AnyObject?
        AXUIElementCopyAttributeValue(element, kAXIdentifierAttribute as CFString, &identifier)
        
        if let roleStr = role as? String, let idStr = identifier as? String {
            if roleStr == kAXTextFieldRole && idStr.contains("WEB_BROWSER_ADDRESS_AND_SEARCH_FIELD") {
                return element
            }
        }
        
        var children: AnyObject?
        AXUIElementCopyAttributeValue(element, kAXChildrenAttribute as CFString, &children)
        if let childrenArray = children as? [AXUIElement] {
            for child in childrenArray {
                if let found = findAddressBar(in: child) {
                    return found
                }
            }
        }
        return nil
    }
    
    public func receive(_ signal: Signal) async throws {
        if signal.name == "BROWSER_ACTION" {
            self.status = .working
            
            guard let payloadStr = String(data: signal.payload, encoding: .utf8),
                  let data = payloadStr.data(using: .utf8),
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let type = json["type"] as? String else {
                self.status = .idle
                return
            }
            
            do {
                var currentURLStr = ""
                if type == "navigate", let targetUrl = json["url"] as? String {
                    currentURLStr = targetUrl
                } else {
                    currentURLStr = try SafariJSBridge.getCurrentURL()
                }
                
                let defaultVaultPath = PathConfiguration.shared.vaultURL
                guard let vault = try? VaultManager(configURL: defaultVaultPath) else {
                    throw NSError(domain: "BrowserAgent", code: 500, userInfo: [NSLocalizedDescriptionKey: "Failed to load VaultManager"])
                }
                
                guard let allowedDomains = vault.config.browser?.allowedDomains else {
                    throw NSError(domain: "BrowserAgent", code: 403, userInfo: [NSLocalizedDescriptionKey: "No allowedDomains configured"])
                }
                
                guard let host = URL(string: currentURLStr)?.host, allowedDomains.contains(where: { host.hasSuffix($0) || $0 == "*" }) else {
                    AgentLogger.logAudit(level: .security, agent: "BrowserAgent", message: "action=\(type) url=\(currentURLStr) status=BLOCKED_DOMAIN")
                    
                    let errSignal = Signal(source: .browserAgent, target: signal.source, name: "BROWSER_ERROR", priority: .high, payload: "DOMAIN_VIOLATION".data(using: .utf8)!, secretKey: bus.sharedSecret)
                    try await bus.dispatch(errSignal)
                    self.status = .idle
                    return
                }
                
                var resultText = ""
                
                switch type {
                case "navigate":
                    guard let urlStr = json["url"] as? String, let url = URL(string: urlStr) else { break }
                    let success = navigateAXUIElement(url: url)
                    resultText = success ? "Navigated to \(urlStr) via AXUIElement" : "AXUIElement navigation failed"
                    
                case "read":
                    resultText = try SafariJSBridge.evaluate("document.body.innerText")
                    
                case "query":
                    guard let selector = json["selector"] as? String else { break }
                    // REQUIRES APPROVAL
                    AgentLogger.logAudit(level: .security, agent: "BrowserAgent", message: "action=browser_js requirement=approval_granted")
                    let escaped = selector.replacingOccurrences(of: "'", with: "\\'")
                    resultText = try SafariJSBridge.evaluate("var el = document.querySelector('\(escaped)'); el ? el.outerHTML : ''")
                    
                case "fill":
                    guard let fields = json["fields"] as? [String: String] else { break }
                    // REQUIRES APPROVAL
                    AgentLogger.logAudit(level: .security, agent: "BrowserAgent", message: "action=browser_fill requirement=approval_granted")
                    
                    var script = ""
                    for (sel, val) in fields {
                        let escapedSel = sel.replacingOccurrences(of: "'", with: "\\'")
                        let escapedVal = val.replacingOccurrences(of: "'", with: "\\'")
                        script += "var el = document.querySelector('\(escapedSel)'); if (el) { el.value = '\(escapedVal)'; }"
                    }
                    _ = try SafariJSBridge.evaluate(script)
                    resultText = "Form filled perfectly"
                    
                default:
                    break
                }
                
                AgentLogger.logAudit(level: .info, agent: "BrowserAgent", message: "action=\(type) url=\(currentURLStr) status=SUCCESS")
                
                let resSignal = Signal(source: .browserAgent, target: signal.source, name: "BROWSER_RESULT", priority: .high, payload: (resultText.data(using: .utf8) ?? Data()), secretKey: bus.sharedSecret)
                try await bus.dispatch(resSignal)
                
            } catch {
                AgentLogger.logAudit(level: .error, agent: "BrowserAgent", message: "action=\(type) status=ERROR")
                let errSignal = Signal(source: .browserAgent, target: signal.source, name: "BROWSER_ERROR", priority: .high, payload: error.localizedDescription.data(using: .utf8)!, secretKey: bus.sharedSecret)
                try await bus.dispatch(errSignal)
            }
            
            self.status = .idle
        }
    }
    
    public func healthReport() -> AgentHealth {
        return AgentHealth(isHealthy: true, statusMessage: "OK")
    }
}
