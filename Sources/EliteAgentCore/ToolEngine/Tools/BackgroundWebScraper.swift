import Foundation
import WebKit

/// A headless web scraper that uses WKWebView to extract text from URLs without visible Safari tabs.
@MainActor
public final class BackgroundWebScraper: NSObject, WKNavigationDelegate {
    public static let shared = BackgroundWebScraper()
    
    private var webView: WKWebView?
    private var completions: [String: (Result<String, Error>) -> Void] = [:]
    
    private override init() {
        super.init()
        setup()
    }
    
    public func setup() {
        let config = WKWebViewConfiguration()
        let prefs = WKWebpagePreferences()
        prefs.allowsContentJavaScript = true
        config.defaultWebpagePreferences = prefs
        
        // v9.9: WebsiteDataStore is non-persistent to ensure no cache accumulation
        config.websiteDataStore = .nonPersistent()
        
        webView = WKWebView(frame: .zero, configuration: config)
        webView?.navigationDelegate = self
        
        AgentLogger.logAudit(level: .info, agent: "WEB_SCRAPER", message: "Headless WKWebView initialized (Session-less)")
    }
    
    /// Scrapes the text content of a URL with a 10-second timeout.
    public func scrapeURL(_ url: URL) async throws -> String {
        AgentLogger.logAudit(level: .info, agent: "WEB_SCRAPER", message: "Scraping started: \(url.host ?? url.absoluteString)")
        
        return try await withTimeout(seconds: 10) { [weak self] (continuation: CheckedContinuation<String, Error>) in
            Task { @MainActor in
                guard let self = self else { 
                    continuation.resume(throwing: NSError(domain: "scraper", code: 0, userInfo: [NSLocalizedDescriptionKey: "Scraper deallocated"]))
                    return 
                }
                
                // Map the continuation to our Result-based completion dictionary
                self.completions[url.absoluteString] = { result in
                    continuation.resume(with: result)
                }
                
                self.webView?.load(URLRequest(url: url))
            }
        }
    }
    
    public func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        guard let url = webView.url else { return }
        
        // Extract plain text from the body
        webView.evaluateJavaScript("document.body.innerText") { [weak self] result, error in
            guard let self = self else { return }
            
            let completion = self.completions[url.absoluteString]
            self.completions.removeValue(forKey: url.absoluteString)
            
            if let error = error {
                AgentLogger.logAudit(level: .error, agent: "WEB_SCRAPER", message: "JavaScript evaluation failed: \(error.localizedDescription)")
                completion?(.failure(error))
            } else {
                let text = result as? String ?? ""
                AgentLogger.logAudit(level: .info, agent: "WEB_SCRAPER", message: "Scraped successfully: \(text.count) characters")
                completion?(.success(text))
            }
            
            // v9.9 Cleanup Logic
            webView.stopLoading()
            // Note: We keep the webView instance alive for subsequent loads, but clean up temporary state
        }
    }
    
    public func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        handleFailure(for: webView.url, error: error)
    }
    
    public func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        handleFailure(for: webView.url, error: error)
    }
    
    private func handleFailure(for url: URL?, error: Error) {
        guard let url = url else { return }
        let completion = completions[url.absoluteString]
        completions.removeValue(forKey: url.absoluteString)
        completion?(.failure(error))
        
        AgentLogger.logAudit(level: .warn, agent: "WEB_SCRAPER", message: "Navigation failed for \(url.absoluteString): \(error.localizedDescription)")
    }
}
