import Foundation

public enum OutputFormat: Sendable {
    case plainText
    case jsonSchema
    case toolCall
}

public struct ValidationResult: Sendable {
    public let isValid: Bool
    public let reason: String?
    public let confidence: Float
    
    public static func valid(confidence: Float = 1.0) -> ValidationResult {
        ValidationResult(isValid: true, reason: nil, confidence: confidence)
    }
    
    public static func invalid(reason: String, confidence: Float = 0.0) -> ValidationResult {
        ValidationResult(isValid: false, reason: reason, confidence: confidence)
    }
}

public struct InferenceValidator {
    
    public static func validate(_ response: String, format: OutputFormat) -> ValidationResult {
        let trimmed = response.trimmingCharacters(in: .whitespacesAndNewlines)
        
        // 1. Empty Check
        guard !trimmed.isEmpty else {
            return .invalid(reason: "empty_response")
        }
        
        // 2. Early Exit for short valid responses (e.g. "Evet", "Hayır", "Tamam")
        if trimmed.count < 10 {
            return .valid(confidence: 0.5)
        }
        
        // 3. Gibberish Detection (Repetition & Entropy)
        // O(n) Single Pass character analysis
        let metrics = analyzeString(trimmed)
        
        if metrics.repetitionRatio > 0.6 {
            return .invalid(reason: "gibberish_repetition", confidence: 0.2)
        }
        
        if metrics.specialCharRatio > 0.4 && format != .jsonSchema {
            return .invalid(reason: "gibberish_noise", confidence: 0.2)
        }
        
        // 4. Format Specific Validation (Lightweight)
        switch format {
        case .jsonSchema:
            if !trimmed.hasPrefix("{") || !trimmed.hasSuffix("}") {
                return .invalid(reason: "invalid_json_structure", confidence: 0.3)
            }
        case .toolCall:
            if !trimmed.contains("\"tool\"") && !trimmed.contains("\"action\"") {
                return .invalid(reason: "missing_tool_call_marker", confidence: 0.3)
            }
        case .plainText:
            break
        }
        
        return .valid(confidence: 0.9)
    }
    
    private struct StringMetrics {
        let repetitionRatio: Double
        let specialCharRatio: Double
    }
    
    private static func analyzeString(_ text: String) -> StringMetrics {
        guard text.count > 0 else { return StringMetrics(repetitionRatio: 0, specialCharRatio: 0) }
        
        var repeatCount = 0
        var specialCount = 0
        let chars = Array(text)
        
        // Simple O(n) sliding window for char repetition
        for i in 1..<chars.count {
            if chars[i] == chars[i-1] {
                repeatCount += 1
            }
            
            // Special char detection (simplified)
            let scalar = chars[i].unicodeScalars.first!
            if !CharacterSet.alphanumerics.contains(scalar) && !CharacterSet.whitespacesAndNewlines.contains(scalar) && !CharacterSet.punctuationCharacters.contains(scalar) {
                specialCount += 1
            }
        }
        
        // Advanced repetition check: Substring repeats (simplified O(n))
        // We check for the same char repeating 5+ times in a row as a clear sign of failure
        var maxConsecutive = 0
        var currentConsecutive = 1
        for i in 1..<chars.count {
            if chars[i] == chars[i-1] {
                currentConsecutive += 1
                maxConsecutive = max(maxConsecutive, currentConsecutive)
            } else {
                currentConsecutive = 1
            }
        }
        
        let finalRepRatio = Double(repeatCount) / Double(text.count)
        let finalSpecRatio = Double(specialCount) / Double(text.count)
        
        // If we have 10+ identical consecutive chars, mark as high repetition
        let adjustedRepRatio = maxConsecutive > 15 ? 0.8 : finalRepRatio
        
        return StringMetrics(repetitionRatio: adjustedRepRatio, specialCharRatio: finalSpecRatio)
    }
}
