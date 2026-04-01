import Foundation
import MLX
import MLXNN

/// Helper class to load MLX weights from Disk and map them to the MistralArchitecture.
public final class ModelLoader {
    public static func loadState(from directory: URL) throws -> [String: MLXArray] {
        let weightsFile = directory.appendingPathComponent("weights.npz")
        guard FileManager.default.fileExists(atPath: weightsFile.path) else {
            throw NSError(domain: "ModelLoader", code: 404, userInfo: [NSLocalizedDescriptionKey: "Weights not found at \(weightsFile.path)"])
        }
        
        // MLX.loadArray returns a dictionary of [String: MLXArray] for .npz files
        return try MLX.loadArrays(url: weightsFile)
    }
    
    public static func apply(state: [String: MLXArray], to model: Module) {
        // MLX modules can be updated using a flattened dictionary or a nested one
        // Here we map the HuggingFace-style keys to our internal Structure
        var updates = [String: MLXArray]()
        
        for (key, value) in state {
            // Mapping logic: e.g. "model.layers.0.input_layernorm.weight" -> "layers.0.input_layernorm.weight"
            let mappedKey = key.replacingOccurrences(of: "model.", with: "")
            updates[mappedKey] = value
        }
        
        model.update(parameters: ModuleParameters.unflattened(updates))
    }
}
