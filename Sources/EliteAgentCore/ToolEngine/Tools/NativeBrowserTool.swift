import Foundation
import Cocoa

public struct NativeBrowserTool: AgentTool {
    public let name: String = "browser_native"
    public let summary: String = "Interactive high-fidelity native browser."
    public let description = "A high-fidelity native browser for navigating and interacting with web pages. Supports 'navigate', 'read', 'screenshot', and 'click'."
    public let ubid: Int128 = 47 // Token 'P' in Qwen 2.5
    
    public init() {}
    
    public func execute(params: [String: AnyCodable], session: Session) async throws(AgentToolError) -> String {
        guard let action = params["action"]?.value as? String else {
            throw AgentToolError.missingParameter("action")
        }
        
        do {
            switch action {
            case "navigate":
                guard let urlStr = params["url"]?.value as? String, let url = URL(string: urlStr) else {
                    throw AgentToolError.missingParameter("url")
                }
                try await BrowserEngine.shared.navigate(to: url)
                return "Successfully navigated to \(urlStr)"
                
            case "read":
                let text = try await BrowserEngine.shared.getInnerText()
                return text
                
            case "screenshot":
                let image = try await BrowserEngine.shared.takeSnapshot()
                let filename = "screenshot_\(Int(Date().timeIntervalSince1970)).png"
                let path = session.workspaceURL.appendingPathComponent(filename)
                
                if let tiffData = image.tiffRepresentation,
                   let bitmap = NSBitmapImageRep(data: tiffData),
                   let pngData = bitmap.representation(using: .png, properties: [:]) {
                    try pngData.write(to: path)
                    return "Screenshot saved to \(filename). Analyzable by VisionAnalyzer."
                } else {
                    throw AgentToolError.executionError("Failed to encode screenshot to PNG")
                }
                
            case "visual_analyze":
                let image = try await BrowserEngine.shared.takeSnapshot()
                let elements = try await VisionAnalyzer.shared.analyze(image: image)
                
                // v13.8: UNO Pure - Shielded encoding for external UI browser data
                guard let payload = UNOExternalBridge.prepareExternalBlob(from: ["elements": elements]) else {
                    return "Browser data encoding failed."
                }
                return String(data: payload, encoding: .utf8) ?? "[]"
                
            case "click_at":
                guard let x = params["x"]?.value as? Double, let y = params["y"]?.value as? Double else {
                    throw AgentToolError.missingParameter("x, y")
                }
                let script = CoordinateBridge.shared.generateClickScript(x: x, y: y)
                let result = try await BrowserEngine.shared.evaluateJavaScript(script)
                return "\(result)"
                
            default:
                throw AgentToolError.invalidParameter("Unknown action: \(action)")
            }
        } catch {
            if let toolError = error as? AgentToolError {
                throw toolError
            }
            throw AgentToolError.executionError(error.localizedDescription)
        }
    }
}
