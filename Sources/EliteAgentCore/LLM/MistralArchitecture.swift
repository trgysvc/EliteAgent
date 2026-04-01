import Foundation
import MLX
import MLXNN

/// Configuration for the Mistral-7B architecture.
public struct MistralConfig: Codable, Sendable {
    public let vocabSize: Int
    public let hiddenSize: Int
    public let intermediateSize: Int
    public let numHiddenLayers: Int
    public let numAttentionHeads: Int
    public let numKeyValueHeads: Int
    public let rmsNormEps: Float
    public let ropeTheta: Float
    public let maxPositionEmbeddings: Int
    
    public static let mistral7B = MistralConfig(
        vocabSize: 32000,
        hiddenSize: 4096,
        intermediateSize: 14336,
        numHiddenLayers: 32,
        numAttentionHeads: 32,
        numKeyValueHeads: 8,
        rmsNormEps: 1e-5,
        ropeTheta: 10000.0,
        maxPositionEmbeddings: 32768
    )
}

/// A single Decoder Layer for the Mistral model.
open class MistralDecoderLayer: Module {
    @ModuleInfo(key: "self_attn") public var attention: MistralAttention
    @ModuleInfo(key: "mlp") public var mlp: MistralMLP
    @ModuleInfo(key: "input_layernorm") public var inputLayerNorm: RMSNorm
    @ModuleInfo(key: "post_attention_layernorm") public var postAttentionLayerNorm: RMSNorm
    
    public init(_ config: MistralConfig) {
        self._attention.wrappedValue = MistralAttention(config)
        self._mlp.wrappedValue = MistralMLP(config)
        self._inputLayerNorm.wrappedValue = RMSNorm(dimensions: config.hiddenSize, eps: config.rmsNormEps)
        self._postAttentionLayerNorm.wrappedValue = RMSNorm(dimensions: config.hiddenSize, eps: config.rmsNormEps)
        super.init()
    }
    
    public func callAsFunction(_ x: MLXArray, mask: MLXArray? = nil, cache: KVCache? = nil) -> MLXArray {
        var h = inputLayerNorm(x)
        h = attention(h, mask: mask, cache: cache)
        let x = x + h
        
        h = postAttentionLayerNorm(x)
        h = mlp(h)
        return x + h
    }
}

/// Multi-head Attention with RoPE and KV Cache support.
open class MistralAttention: Module {
    @ModuleInfo(key: "q_proj") public var qProj: Linear
    @ModuleInfo(key: "k_proj") public var kProj: Linear
    @ModuleInfo(key: "v_proj") public var vProj: Linear
    @ModuleInfo(key: "o_proj") public var oProj: Linear
    public let rope: RoPE
    
    public let numHeads: Int
    public let numKVHeads: Int
    public let headDim: Int
    
    public init(_ config: MistralConfig) {
        self.numHeads = config.numAttentionHeads
        self.numKVHeads = config.numKeyValueHeads
        self.headDim = config.hiddenSize / config.numAttentionHeads
        
        self._qProj.wrappedValue = Linear(config.hiddenSize, config.numAttentionHeads * headDim, bias: false)
        self._kProj.wrappedValue = Linear(config.hiddenSize, config.numKeyValueHeads * headDim, bias: false)
        self._vProj.wrappedValue = Linear(config.hiddenSize, config.numKeyValueHeads * headDim, bias: false)
        self._oProj.wrappedValue = Linear(config.numAttentionHeads * headDim, config.hiddenSize, bias: false)
        
        self.rope = RoPE(dimensions: headDim, traditional: false, base: config.ropeTheta)
        super.init()
    }
    
    public func callAsFunction(_ x: MLXArray, mask: MLXArray? = nil, cache: KVCache? = nil) -> MLXArray {
        let q = qProj(x)
        let k = kProj(x)
        let v = vProj(x)
        
        let batchSize = q.dim(0)
        let sourceL = q.dim(1)
        
        // Split heads and apply RoPE
        var qH = q.reshaped(batchSize, sourceL, numHeads, headDim).transposed(0, 2, 1, 3)
        var kH = k.reshaped(batchSize, sourceL, numKVHeads, headDim).transposed(0, 2, 1, 3)
        let vH = v.reshaped(batchSize, sourceL, numKVHeads, headDim).transposed(0, 2, 1, 3)
        
        // Applying RoPE (Rotary Positional Embeddings)
        let offset = cache?.offset ?? 0
        qH = rope(qH, offset: offset)
        kH = rope(kH, offset: offset)
        
        // Update KV Cache if available
        var kFinal = kH
        var vFinal = vH
        if let cache = cache {
            kFinal = cache.updateKey(kH)
            vFinal = cache.updateValue(vH)
        }
        
        // Scaled Dot Product Attention (SDPA)
        let scale = sqrt(1.0 / Float(headDim))
        var scores = matmul(qH, kFinal.transposed(0, 1, 3, 2)) * scale
        
        if let mask = mask {
            scores = scores + mask
        }
        
        let weights = softmax(scores.asType(.float32), axis: -1).asType(scores.dtype)
        var output = matmul(weights, vFinal)
        
        // Reshape and project out
        output = output.transposed(0, 2, 1, 3).reshaped(batchSize, sourceL, numHeads * headDim)
        return oProj(output)
    }
}

/// Key-Value Cache for faster auto-regressive generation.
public final class KVCache {
    public var keys: MLXArray?
    public var values: MLXArray?
    public var offset: Int = 0
    
    public init() {}
    
    public func updateKey(_ k: MLXArray) -> MLXArray {
        if let keys = keys {
            let updated = concatenated([keys, k], axis: 2)
            self.keys = updated
            return updated
        }
        self.keys = k
        return k
    }
    
    public func updateValue(_ v: MLXArray) -> MLXArray {
        if let values = values {
            let updated = concatenated([values, v], axis: 2)
            self.values = updated
            return updated
        }
        self.values = v
        return v
    }
}
open class MistralMLP: Module {
    @ModuleInfo(key: "gate_proj") public var gateProj: Linear
    @ModuleInfo(key: "down_proj") public var downProj: Linear
    @ModuleInfo(key: "up_proj") public var upProj: Linear
    
    public init(_ config: MistralConfig) {
        self._gateProj.wrappedValue = Linear(config.hiddenSize, config.intermediateSize, bias: false)
        self._downProj.wrappedValue = Linear(config.intermediateSize, config.hiddenSize, bias: false)
        self._upProj.wrappedValue = Linear(config.hiddenSize, config.intermediateSize, bias: false)
        super.init()
    }
    
    public func callAsFunction(_ x: MLXArray) -> MLXArray {
        return downProj(silu(gateProj(x)) * upProj(x))
    }
}

/// The top-level Mistral Model.
open class MistralModel: Module {
    @ModuleInfo(key: "embed_tokens") public var embedTokens: Embedding
    @ModuleInfo(key: "layers") public var layers: [MistralDecoderLayer]
    @ModuleInfo(key: "norm") public var norm: RMSNorm
    @ModuleInfo(key: "lm_head") public var lmHead: Linear
    
    public init(_ config: MistralConfig) {
        self._embedTokens.wrappedValue = Embedding(embeddingCount: config.vocabSize, dimensions: config.hiddenSize)
        self._layers.wrappedValue = (0..<config.numHiddenLayers).map { _ in MistralDecoderLayer(config) }
        self._norm.wrappedValue = RMSNorm(dimensions: config.hiddenSize, eps: config.rmsNormEps)
        self._lmHead.wrappedValue = Linear(config.hiddenSize, config.vocabSize, bias: false)
        super.init()
    }
    
    public func callAsFunction(_ x: MLXArray, cache: [KVCache]? = nil) -> MLXArray {
        var h = embedTokens(x)
        for (i, layer) in layers.enumerated() {
            h = layer(h, cache: cache?[i])
        }
        h = norm(h)
        return lmHead(h)
    }
}
