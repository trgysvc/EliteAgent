import Foundation
import Cocoa

public struct ImageAnalysisTool: AgentTool, Sendable {
    public let name = "analyze_image"
    public let description = "Analyzes a local image file using VisionAnalyzer for text and potential interactive elements."
    
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
        
        let encoder = JSONEncoder()
        encoder.outputFormatting = .prettyPrinted
        let data = try encoder.encode(elements)
        
        guard let jsonString = String(data: data, encoding: .utf8) else {
            throw ToolError.executionError("Failed to encode visual elements to JSON.")
        }
        
        return "SUCCESS: Analyzed \(elements.count) visual elements.\n\(jsonString)"
    }
}
