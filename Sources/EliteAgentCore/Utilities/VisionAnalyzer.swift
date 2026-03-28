import Foundation
import Vision
import Cocoa

public struct VisualElement: Codable, Sendable {
    public let label: String
    public let rect: CGRect // Normalized (0...1)
    public let type: String // "text", "button", "input"
}

public final class VisionAnalyzer: Sendable {
    public static let shared = VisionAnalyzer()
    
    private init() {}
    
    public func analyze(image: NSImage) async throws -> [VisualElement] {
        guard let tiffData = image.tiffRepresentation,
              let cgImage = NSBitmapImageRep(data: tiffData)?.cgImage else {
            throw NSError(domain: "VisionAnalyzer", code: 1, userInfo: [NSLocalizedDescriptionKey: "Failed to create CGImage"])
        }
        
        let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
        
        // 1. OCR (Text Recognition)
        let ocrRequest = VNRecognizeTextRequest()
        ocrRequest.recognitionLevel = .accurate
        ocrRequest.usesLanguageCorrection = true
        
        // 2. Rectangle Detection (Buttons/Inputs)
        let rectRequest = VNDetectRectanglesRequest()
        rectRequest.minimumAspectRatio = 0.1
        rectRequest.maximumObservations = 50
        
        try handler.perform([ocrRequest, rectRequest])
        
        var elements: [VisualElement] = []
        
        // Process OCR
        if let results = ocrRequest.results {
            for result in results {
                if let topCandidate = result.topCandidates(1).first {
                    let rect = VNImageRectForNormalizedRect(result.boundingBox, 1, 1)
                    elements.append(VisualElement(
                        label: topCandidate.string,
                        rect: rect,
                        type: "text"
                    ))
                }
            }
        }
        
        // Process Rectangles (Potential Buttons)
        if let results = rectRequest.results {
            for result in results {
                let rect = VNImageRectForNormalizedRect(result.boundingBox, 1, 1)
                elements.append(VisualElement(
                    label: "potential_button",
                    rect: rect,
                    type: "button"
                ))
            }
        }
        
        return elements
    }
    
    /// Translates normalized Vision coordinates to WebView coordinates (top-left origin).
    public static func mapToWebView(rect: CGRect, width: Double, height: Double) -> CGRect {
        // Vision: (0,0) is bottom-left. WebView: (0,0) is top-left.
        let x = rect.origin.x * width
        let y = (1.0 - rect.origin.y - rect.size.height) * height
        let w = rect.size.width * width
        let h = rect.size.height * height
        return CGRect(x: x, y: y, width: w, height: h)
    }
}
