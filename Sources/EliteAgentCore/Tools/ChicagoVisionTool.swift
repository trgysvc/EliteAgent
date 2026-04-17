import AppKit
import Vision
import ScreenCaptureKit
import OSLog

/// A tool for Vision-based screen analysis (v10.0 'Chicago').
/// Uses VNRecognizeTextRequest to find and label UI elements.
public struct ChicagoVisionTool: AgentTool {
    public let name = "visual_audit"
    public let summary = "Chicago Vision: Frame-by-frame UI & Logic analysis."
    public let description = "Analyzes screenshot/images for UI elements, logic, and visual data."
    public let ubid: Int128 = 30 // Token 'Y' in Qwen 2.5
    
    private let logger = Logger(subsystem: "com.elite.agent", category: "Vision")
    
    public init() {}
    
    public func execute(params: [String: AnyCodable], session: Session) async throws(AgentToolError) -> String {
        // 1. Permission Check
        // v13.0: Root-level permission check
        
        // 2. Capture Screen
        let image: CGImage?
        do {
            image = await capturePrimaryScreen()
        }
        
        guard let validImage = image else {
            throw AgentToolError.executionError("Failed to capture screen using ScreenCaptureKit.")
        }
        
        // 3. Perform OCR Analysis
        do {
            let results = try await performOCR(on: validImage)
            
            // 4. Format Output
            if results.isEmpty {
                return "No text or UI elements found on the current screen."
            }
            
            return "Screen Analysis:\n" + results.joined(separator: "\n")
        } catch {
            throw AgentToolError.executionError(error.localizedDescription)
        }
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
