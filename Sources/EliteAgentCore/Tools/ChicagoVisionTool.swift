import AppKit
import Vision
import ScreenCaptureKit
import OSLog

/// A tool for Vision-based screen analysis (v10.0 'Chicago').
/// Uses VNRecognizeTextRequest to find and label UI elements.
public actor ChicagoVisionTool: AgentTool {
    public let name = "chicago_vision"
    public let description = "Analyzes the screen using OCR and Computer Vision to identify UI elements."
    
    private let logger = Logger(subsystem: "com.elite.agent", category: "Vision")
    
    public init() {}
    
    public func execute(params: [String: AnyCodable], session: Session) async throws -> String {
        // 1. Permission Check
        guard AXIsProcessTrusted() else {
            logger.error("Accessibility permissions denied.")
            return "Error: Accessibility permissions are required for Chicago Vision. Falling back to DegradedMode."
        }
        
        // 2. Capture Screen
        guard let image = await capturePrimaryScreen() else {
            return "Error: Failed to capture screen using ScreenCaptureKit."
        }
        
        // 3. Perform OCR Analysis
        let results = try await performOCR(on: image)
        
        // 4. Format Output
        if results.isEmpty {
            return "No text or UI elements found on the current screen."
        }
        
        return "Screen Analysis:\n" + results.joined(separator: "\n")
    }
    
    private func capturePrimaryScreen() async -> CGImage? {
        do {
            let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
            guard let display = content.displays.first else { return nil }
            
            let filter = SCContentFilter(display: display, excludingWindows: [])
            let config = SCStreamConfiguration()
            config.width = Int(display.width)
            config.height = Int(display.height)
            
            return try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config)
        } catch {
            logger.error("ScreenCaptureKit failed: \(error.localizedDescription)")
            return nil
        }
    }
    
    private func performOCR(on image: CGImage) async throws -> [String] {
        return try await withCheckedThrowingContinuation { continuation in
            let request = VNRecognizeTextRequest { request, error in
                if let error = error {
                    continuation.resume(throwing: error)
                    return
                }
                
                let results = request.results as? [VNRecognizedTextObservation] ?? []
                let output = results.compactMap { observation -> String? in
                    guard let topCandidate = observation.topCandidates(1).first else { return nil }
                    let box = observation.boundingBox
                    return "- [\(topCandidate.string)] at (\(box.origin.x.rounded()), \(box.origin.y.rounded()))"
                }
                continuation.resume(returning: output)
            }
            
            request.recognitionLevel = .accurate
            let handler = VNImageRequestHandler(cgImage: image, options: [:])
            
            do {
                try handler.perform([request])
            } catch {
                continuation.resume(throwing: error)
            }
        }
    }
}

fileprivate func AXIsProcessTrusted() -> Bool {
    return true // Simplified for prototype. In production, use AXIsProcessTrustedWithOptions
}
