import Foundation
import MLX

/// Automatically tunes EliteAgent settings based on hardware and thermal state.
public final class AutoConfigManager: Sendable {
    public static let shared = AutoConfigManager()
    
    public enum ThermalPreset: String, Codable {
        case balanced    // M4/M4 Air
        case performance // M4 Pro/Max
        case lowPower    // Battery saver
    }
    
    private init() {}
    
    /// Detects hardware and applies optimized LLM settings.
    public func autoTune() -> (preset: ThermalPreset, context: Int, gpuLayers: Int) {
        let physicalMemory = ProcessInfo.processInfo.physicalMemory
        let processorCount = ProcessInfo.processInfo.activeProcessorCount
        
        // 1. Detect Thermal Preset
        let preset: ThermalPreset
        if processorCount >= 10 && physicalMemory >= 32 * 1024 * 1024 * 1024 {
            preset = .performance // Likely M4 Max / M3 Max
        } else if physicalMemory >= 16 * 1024 * 1024 * 1024 {
            preset = .balanced    // M4/M3 with 16GB
        } else {
            preset = .lowPower    // 8GB RAM devices
        }
        
        // 2. Optimized Context Window
        let context: Int
        switch preset {
        case .performance: context = 32768
        case .balanced:    context = 16384
        case .lowPower:    context = 8192
        }
        
        // 3. GPU Allocation (Layers to offload)
        // MLX handles this dynamically, but we can set constraints for specific models.
        let gpuLayers = (preset == .performance) ? 100 : 80
        
        return (preset, context, gpuLayers)
    }
    
    /// Hardware analysis for model recommendations.
    public struct HardwareRecommendation {
        public let ram: UInt64 = ProcessInfo.processInfo.physicalMemory
        public let cores: Int = ProcessInfo.processInfo.processorCount
        private let GB: UInt64 = 1024 * 1024 * 1024

        public enum PerformanceTier {
            case low      // < 12GB RAM
            case balanced // 12GB - 24GB RAM
            case high     // > 24GB RAM
        }

        public var recommendedTier: PerformanceTier {
            if ram >= 32 * GB {
                return .high
            } else if ram >= 12 * GB {
                return .balanced
            } else {
                return .low
            }
        }

        public var thermalPreset: ThermalPreset {
            if cores >= 10 { // M4 Max / Pro
                return .performance
            } else if cores >= 8 { // M4 Air
                return .balanced
            } else {
                return .lowPower
            }
        }
        
        public var ramDescription: String {
            return "\(ram / GB)GB RAM"
        }
    }

    public var recommendation: HardwareRecommendation {
        return HardwareRecommendation()
    }
}
