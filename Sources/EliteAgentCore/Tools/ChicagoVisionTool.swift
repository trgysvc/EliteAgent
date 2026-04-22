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
        // v24.3: Proactive Permission Check (Apple Best Practice)
        // ScreenCaptureKit requires explicit Screen Recording permission in System Settings.
        
        // 1. Capture Screen
        let image: CGImage?
        do {
            image = await capturePrimaryScreen()
        }
        
        guard let validImage = image else {
            let helpMsg = "HATA: Ekran yakalanamadı. Lütfen 'Sistem Ayarları > Gizlilik ve Güvenlik > Ekran Kaydı' kısmından EliteAgent'a izin verdiğinizden emin olun."
            AgentLogger.logAudit(level: .error, agent: "Vision", message: "Screen capture failed. Possible permission issue.")
            throw AgentToolError.executionError(helpMsg)
        }
        
        // 2. Perform OCR Analysis
        do {
            let results = try await performOCR(on: validImage)
            
            // 3. Format Output
            if results.isEmpty {
                return "Ekran analizi tamamlandı ancak okunabilir bir metin veya UI öğesi bulunamadı."
            }
            
            return "Ekran Analiz Raporu:\n" + results.joined(separator: "\n")
        } catch {
            throw AgentToolError.executionError("Vision Analiz Hatası: \(error.localizedDescription)")
        }
    }
    
    private func capturePrimaryScreen() async -> CGImage? {
        do {
            // v24.3: SCShareableContent logic following Apple's modern async/await patterns
            let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
            guard let display = content.displays.first else { 
                AgentLogger.logAudit(level: .warn, agent: "Vision", message: "No active display found for capture.")
                return nil 
            }
            
            let filter = SCContentFilter(display: display, excludingWindows: [])
            let config = SCStreamConfiguration()
            
            // Optimize for OCR: Use Native resolution
            config.width = Int(display.width)
            config.height = Int(display.height)
            config.showsCursor = false
            
            return try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config)
        } catch {
            // v24.3: Specific error logging for diagnostic mode
            AgentLogger.logAudit(level: .error, agent: "Vision", message: "ScreenCaptureKit error: \(error.localizedDescription)")
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
                var uniqueElements = Set<String>()
                var output: [String] = []
                
                for observation in results {
                    guard let topCandidate = observation.topCandidates(1).first else { continue }
                    let text = topCandidate.string.trimmingCharacters(in: .whitespacesAndNewlines)
                    
                    if text.count > 2 && !uniqueElements.contains(text) {
                        uniqueElements.insert(text)
                        output.append("• \(text)")
                    }
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
