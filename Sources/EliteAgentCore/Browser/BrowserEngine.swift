import Foundation
import WebKit
import Cocoa

@MainActor
public final class BrowserEngine: NSObject, WKNavigationDelegate {
    public static let shared = BrowserEngine()
    
    private var webView: WKWebView!
    private var navigationContinuation: CheckedContinuation<Void, Error>?
    
    private override init() {
        super.init()
        let config = WKWebViewConfiguration()
        config.applicationNameForUserAgent = "EliteAgent/3.1 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Safari/605.1.15"
        
        self.webView = WKWebView(frame: .zero, configuration: config)
        self.webView.navigationDelegate = self
    }
    
    public func navigate(to url: URL) async throws {
        // Cancel any pending navigation to avoid continuation misuse
        if let pending = navigationContinuation {
            AgentLogger.logInfo("Cancelling previous navigation to start new one.", agent: "BrowserEngine")
            pending.resume(throwing: URLError(.cancelled))
            navigationContinuation = nil
        }
        
        return try await withCheckedThrowingContinuation { continuation in
            self.navigationContinuation = continuation
            self.webView.load(URLRequest(url: url))
        }
    }
    
    public func evaluateJavaScript(_ script: String) async throws -> String {
        return try await withCheckedThrowingContinuation { continuation in
            self.webView.evaluateJavaScript(script) { result, error in
                if let error = error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: "\(result ?? "")")
                }
            }
        }
    }
    
    public func takeSnapshot() async throws -> NSImage {
        return try await withCheckedThrowingContinuation { continuation in
            let config = WKSnapshotConfiguration()
            self.webView.takeSnapshot(with: config) { image, error in
                if let error = error {
                    continuation.resume(throwing: error)
                } else if let image = image {
                    continuation.resume(returning: image)
                } else {
                    continuation.resume(throwing: NSError(domain: "BrowserEngine", code: 2, userInfo: [NSLocalizedDescriptionKey: "Snapshot failed"]))
                }
            }
        }
    }
    
    public func getContent() async throws -> String {
        let result = try await webView.evaluateJavaScript("document.documentElement.outerHTML")
        return result as? String ?? ""
    }
    
    public func getInnerText() async throws -> String {
        let result = try await webView.evaluateJavaScript("document.body.innerText")
        return result as? String ?? ""
    }
    
    // MARK: - WKNavigationDelegate
    
    public func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        navigationContinuation?.resume()
        navigationContinuation = nil
    }
    
    public func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        navigationContinuation?.resume(throwing: error)
        navigationContinuation = nil
    }
    
    public func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        navigationContinuation?.resume(throwing: error)
        navigationContinuation = nil
    }
}
