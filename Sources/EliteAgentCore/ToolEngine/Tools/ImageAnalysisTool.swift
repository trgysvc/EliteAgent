import Foundation
import Cocoa

public struct ImageAnalysisTool: AgentTool, Sendable {
    public let name = "analyze_image"
    public let summary = "Local OS Vision (OCR / Element Detection)."
    public let description = "Analyzes a local image file using VisionAnalyzer for text and potential interactive elements."
    public let ubid = 48 // Token 'Q' in Qwen 2.5
    
    public init() {}
    
    public func execute(params: [String: AnyCodable], session: Session) async throws -> String {
        guard let path = params["path"]?.value as? String else {
            throw ToolError.missingParameter("path")
        }
        
        let fileURL: URL
        if path.hasPrefix("file://") {
            fileURL = URL(string: path)!
        } else if path.hasPrefix("/") || path.hasPrefix("~") {
            let expandedPath = NSString(string: path).expandingTildeInPath
            fileURL = URL(fileURLWithPath: expandedPath)
        } else {
            fileURL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath).appendingPathComponent(path)
        }
        
        guard let image = NSImage(contentsOf: fileURL) else {
            throw ToolError.executionError("Failed to load image from path: \(path)")
        }
        
        let elements = try await VisionAnalyzer.shared.analyze(image: image)
        
        // v13.8: UNO Pure - Pure Markdown Vision Report (No JSON)
        var report = "ANALİZ TAMAMLANDI: \(elements.count) görsel öğe bulundu.\n\n"
        report += "| Tip | İçerik / Etiket | Koordinatlar (x,y,w,h) |\n"
        report += "| :--- | :--- | :--- |\n"
        
        for element in elements {
            let rect = element.rect
            let coords = String(format: "(%.1f, %.1f, %.1f, %.1f)", rect.origin.x, rect.origin.y, rect.size.width, rect.size.height)
            let label = element.label
            report += "| \(element.type) | \(label) | \(coords) |\n"
        }
        
        return report
    }
}
