import Foundation
import MLX
import MLXLLM
import MLXLMCommon
import MLXNN

/// Bridges Qwen3_5ForCausalLM weights to the Qwen3Next inference path.
///
/// Qwen3_5ForCausalLM exports all tensors under a "language_model.*" prefix
/// (the same VLM-style wrapper convention used by Qwen2-VL). This class
/// matches that weight layout by declaring a single @ModuleInfo child with
/// key "language_model", containing a Qwen3NextModel.  MLX's parameter-update
/// path then resolves:
///
///   language_model.model.layers.N.linear_attn.* → languageModel.model.layers[N].linearAttn.*
///   language_model.model.layers.N.self_attn.*   → languageModel.model.layers[N].selfAttn.*
///   language_model.lm_head.*                    → languageModel.lmHead.*
///
/// The model is architecturally identical to Qwen3Next: 3 linear-attention
/// layers followed by 1 full-attention layer, repeating (full_attention_interval=4).
/// MoE is disabled via num_experts=0 in the patched config.json.
public final class Qwen35Bridge: Module, MLXLLM.LLMModel, KVCacheDimensionProvider {

    @ModuleInfo(key: "language_model") private var language_model: Qwen3NextModel
    private let configDict: [String: Any]

    public var vocabularySize: Int { language_model.vocabularySize }
    public var kvHeads: [Int] { language_model.kvHeads }
    public var loraLayers: [Module] { language_model.loraLayers }

    public init(_ config: Qwen3NextConfiguration, configData: Data) {
        self.configDict = (try? JSONSerialization.jsonObject(with: configData) as? [String: Any]) ?? [:]
        self._language_model.wrappedValue = Qwen3NextModel(config)
    }

    public func callAsFunction(_ inputs: MLXArray, cache: [KVCache]?) -> MLXArray {
        language_model(inputs, cache: cache)
    }

    // Critical: linear-attention layers need MambaCache, not KVCacheSimple.
    // Delegate to Qwen3NextModel.newCache which creates the correct cache type
    // per layer (MambaCache for linear, KVCacheSimple for full-attention).
    public func newCache(parameters: GenerateParameters?) -> [KVCache] {
        language_model.newCache(parameters: parameters)
    }

    public func sanitize(weights: [String: MLXArray]) -> [String: MLXArray] {
        var sanitizedWeights = weights
        
        // 1. Strip MTP (Multi-Token Prediction) weights which are not supported by the bridge
        for key in sanitizedWeights.keys where key.contains("mtp.") {
            sanitizedWeights.removeValue(forKey: key)
        }
        
        // 2. Handle tie_word_embeddings
        let tieWordEmbeddings = configDict["tie_word_embeddings"] as? Bool ?? false
        if tieWordEmbeddings {
            sanitizedWeights["language_model.lm_head.weight"] = nil
        }
        
        // 3. Linear Attention Weight Fusion (Fusing split HF projections into fused Qwen3Next layers)
        // Qwen3.5 HF: in_proj_qkv (q,k,v) + in_proj_z (z) -> in_proj_qkvz
        // Qwen3.5 HF: in_proj_b (b) + in_proj_a (a) -> in_proj_ba
        // IMPORTANT: Must fuse .weight, .scales, AND .biases for quantized models to load correctly.
        let hiddenLayers = configDict["num_hidden_layers"] as? Int ?? 0
        let weightComponents = ["weight", "scales", "biases"]
        
        for i in 0..<hiddenLayers {
            let prefix = "language_model.model.layers.\(i).linear_attn"
            
            for component in weightComponents {
                let suffix = ".\(component)"
                
                // Fuse QKV + Z -> QKVZ
                let qkvKey = "\(prefix).in_proj_qkv\(suffix)"
                let zKey = "\(prefix).in_proj_z\(suffix)"
                if let qkv = sanitizedWeights[qkvKey], let z = sanitizedWeights[zKey] {
                    sanitizedWeights["\(prefix).in_proj_qkvz\(suffix)"] = concatenated([qkv, z], axis: 0)
                    sanitizedWeights.removeValue(forKey: qkvKey)
                    sanitizedWeights.removeValue(forKey: zKey)
                    if i == 0 && component == "weight" {
                        AgentLogger.logAudit(level: .info, agent: "titan", message: "Fusing QKVZ for layer 0: \(qkv.shape) + \(z.shape) -> \(sanitizedWeights["\(prefix).in_proj_qkvz\(suffix)"]?.shape ?? [])")
                    }
                }
                
                // Fuse B + A -> BA
                let bKey = "\(prefix).in_proj_b\(suffix)"
                let aKey = "\(prefix).in_proj_a\(suffix)"
                if let b = sanitizedWeights[bKey], let a = sanitizedWeights[aKey] {
                    sanitizedWeights["\(prefix).in_proj_ba\(suffix)"] = concatenated([b, a], axis: 0)
                    sanitizedWeights.removeValue(forKey: bKey)
                    sanitizedWeights.removeValue(forKey: aKey)
                    if i == 0 && component == "weight" {
                        AgentLogger.logAudit(level: .info, agent: "titan", message: "Fusing BA for layer 0: \(b.shape) + \(a.shape) -> \(sanitizedWeights["\(prefix).in_proj_ba\(suffix)"]?.shape ?? [])")
                    }
                }
            }
        }
        
        // v24.8: Force evaluation of fused tensors to allow original shards to be purged from cache
        MLX.eval(Array(sanitizedWeights.values))
        
        // 4. Common Qwen/MLX Sanitizations (Conv1D axes and Norm offsets)
        let normSuffixes = [
            ".input_layernorm.weight",
            ".post_attention_layernorm.weight",
            "model.norm.weight",
            ".q_norm.weight",
            ".k_norm.weight",
        ]
        
        for key in Array(sanitizedWeights.keys) {
            guard let value = sanitizedWeights[key] else { continue }
            
            // Conv1D: Moved axis for MLX performance
            if key.contains("conv1d.weight") && value.dim(-1) != 1 {
                sanitizedWeights[key] = value.movedAxis(source: 2, destination: 1)
            }
            
            // Norms: Qwen often stores weight as offset from 1.0
            if normSuffixes.contains(where: { key.hasSuffix($0) }) && value.ndim == 1 {
                sanitizedWeights[key] = value + 1.0
            }
        }
        
        return sanitizedWeights
    }
}
