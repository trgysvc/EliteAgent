import Foundation
import Cocoa

public struct NativeBrowserTool: AgentTool {
    public let name: String = "browser_native"
    public let description: String = "A high-fidelity native browser for navigating and interacting with web pages. Supports 'navigate', 'read', 'screenshot', and 'click'."
    
    public init() {}
    
    public func execute(params: [String: AnyCodable], session: Session) async throws -> String {
        guard let action = params["action"]?.value as? String else {
            throw ToolError.missingParameter("action")
        }
        
        switch action {
        case "navigate":
            guard let urlStr = params["url"]?.value as? String, let url = URL(string: urlStr) else {
                throw ToolError.missingParameter("url")
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
                throw ToolError.executionError("Failed to encode screenshot to PNG")
            }
            
        case "visual_analyze":
            let image = try await BrowserEngine.shared.takeSnapshot()
            let elements = try await VisionAnalyzer.shared.analyze(image: image)
            let result = try JSONEncoder().encode(elements)
            return String(data: result, encoding: .utf8) ?? "[]"
            
        case "click_at":
            guard let x = params["x"]?.value as? Double, let y = params["y"]?.value as? Double else {
                throw ToolError.missingParameter("x, y")
            }
            let script = CoordinateBridge.shared.generateClickScript(x: x, y: y)
            let result = try await BrowserEngine.shared.evaluateJavaScript(script)
            return "\(result)"
            
        default:
            throw ToolError.invalidParameter("Unknown action: \(action)")
        }
    }
}
