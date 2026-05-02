import Foundation

/// Specific error types for EliteAgent v9.0 Model Management.
public enum ModelError: Error, LocalizedError {
    case incompleteDownload(missing: String)
    case unknown(String)
    case vramInstruction(String)
    
    public var errorDescription: String? {
        switch self {
        case .incompleteDownload(let file):
            return "Metadata eksik: \(file). Lütfen 'Tamamla' butonuna basarak eksik dosyayı indirin."
        case .unknown(let msg):
            return "Bilinmeyen model hatası: \(msg)"
        case .vramInstruction(let msg):
            return "VRAM/Bellek Hatası: \(msg)"
        }
    }
}

public enum InferenceError: Error, Sendable {
    case localProviderUnavailable(String)
}
