import Foundation

/// Defines where and how a model is executed.
public enum ModelProvider: Codable, Sendable, Equatable {
    case none
    case localTitanEngine(modelID: String)  // Native MLX
    case cloudOpenRouter(modelID: String)   // Gemini, Claude, etc.
}

/// Metadata for a specific AI model in the EliteAgent ecosystem.
public struct ModelCatalog: Identifiable, Codable, Sendable {
    public let id: String
    public let author: String
    public let name: String
    public let size: String
    public let quantization: String
    public let minRAM: String
    public let recommendedContext: String
    public let downloadURL: String
    public let sha256: String
    public let estimatedSpeed: String
    public let provider: ModelProvider
    /// ID of the companion draft model for speculative decoding. nil = no draft model.
    public let draftModelID: String?

    public init(
        id: String,
        author: String = "mlx-community",
        name: String,
        size: String,
        quantization: String,
        minRAM: String,
        recommendedContext: String,
        downloadURL: String,
        sha256: String,
        estimatedSpeed: String,
        provider: ModelProvider,
        draftModelID: String? = nil
    ) {
        self.id = id
        self.author = author
        self.name = name
        self.size = size
        self.quantization = quantization
        self.minRAM = minRAM
        self.recommendedContext = recommendedContext
        self.downloadURL = downloadURL
        self.sha256 = sha256
        self.estimatedSpeed = estimatedSpeed
        self.provider = provider
        self.draftModelID = draftModelID
    }
}

/// The authorized list of models for EliteAgent v9.0.
public struct ModelRegistry {

    // MARK: - Draft Models (internal — never shown in model picker)
    // Downloaded automatically in the background after the paired main model loads.
    // Tokenizer family compatibility is required for speculative decoding.
    public static let draftModels: [ModelCatalog] = [
        // Qwen3.5 tokenizer family — vocab:248044, model_type:qwen3_5
        // Compatible ONLY with Qwen3.5-series main models (NOT Qwen2.5).
        ModelCatalog(
            id: "qwen-3.5-0.8b-4bit",
            author: "mlx-community",
            name: "Qwen 3.5 0.8B Draft",
            size: "0.5 GB",
            quantization: "4-bit",
            minRAM: "2 GB",
            recommendedContext: "8K",
            downloadURL: "https://huggingface.co/mlx-community/Qwen3.5-0.8B-4bit/resolve/main/model.safetensors",
            sha256: "",
            estimatedSpeed: "~180 tok/s on M4",
            provider: .localTitanEngine(modelID: "qwen-3.5-0.8b-4bit")
        ),
        // Qwen2.5 tokenizer family — vocab:151643, model_type:qwen2
        // Compatible ONLY with Qwen2.5-series main models (NOT Qwen3.5).
        ModelCatalog(
            id: "qwen-2.5-0.5b-instruct-4bit",
            author: "mlx-community",
            name: "Qwen 2.5 0.5B Draft",
            size: "0.35 GB",
            quantization: "4-bit",
            minRAM: "1 GB",
            recommendedContext: "8K",
            downloadURL: "https://huggingface.co/mlx-community/Qwen2.5-0.5B-Instruct-4bit/resolve/main/model.safetensors",
            sha256: "",
            estimatedSpeed: "~200 tok/s on M4",
            provider: .localTitanEngine(modelID: "qwen-2.5-0.5b-instruct-4bit")
        ),
        // Llama 3.2 tokenizer family — compatible with Llama 3.x main models
        ModelCatalog(
            id: "llama-3.2-1b-instruct-4bit",
            author: "mlx-community",
            name: "Llama 3.2 1B Draft",
            size: "0.7 GB",
            quantization: "4-bit",
            minRAM: "2 GB",
            recommendedContext: "8K",
            downloadURL: "https://huggingface.co/mlx-community/Llama-3.2-1B-Instruct-4bit/resolve/main/model.safetensors",
            sha256: "",
            estimatedSpeed: "~160 tok/s on M4",
            provider: .localTitanEngine(modelID: "llama-3.2-1b-instruct-4bit")
        ),
    ]

    /// All models (main + draft) for internal lookups.
    public static let allModels: [ModelCatalog] = availableModels + draftModels

    public static let availableModels: [ModelCatalog] = [
        // MARK: - LOCAL TITAN MODELS (MLX Optimized)
        
        ModelCatalog(
            id: "qwen-2.5-7b-coder-4bit",
            author: "mlx-community",
            name: "Qwen 2.5 Coder 7B (Instruct)",
            size: "4.5 GB",
            quantization: "4-bit",
            minRAM: "8 GB",
            recommendedContext: "32K",
            downloadURL: "https://huggingface.co/mlx-community/Qwen2.5-Coder-7B-Instruct-4bit/resolve/main/model.safetensors",
            sha256: "a1b2...",
            estimatedSpeed: "~45 tok/s on M4",
            provider: .localTitanEngine(modelID: "qwen-2.5-7b-coder-4bit"),
            draftModelID: "qwen-2.5-0.5b-instruct-4bit"
        ),

        ModelCatalog(
            id: "qwen-2.5-14b-coder-4bit",
            author: "mlx-community",
            name: "Qwen 2.5 Coder 14B (Instruct)",
            size: "8.5 GB",
            quantization: "4-bit",
            minRAM: "16 GB",
            recommendedContext: "32K",
            downloadURL: "https://huggingface.co/mlx-community/Qwen2.5-Coder-14B-Instruct-4bit/resolve/main/model-00001-of-00002.safetensors",
            sha256: "b4c1...",
            estimatedSpeed: "~20 tok/s on M4",
            provider: .localTitanEngine(modelID: "qwen-2.5-14b-coder-4bit"),
            draftModelID: "qwen-2.5-0.5b-instruct-4bit"
        ),

        ModelCatalog(
            id: "qwen-2.5-14b-coder-abliterated-4bit",
            author: "mlx-community",
            name: "Qwen 2.5 Coder 14B (Abliterated)",
            size: "8.5 GB",
            quantization: "4-bit",
            minRAM: "16 GB",
            recommendedContext: "32K",
            downloadURL: "https://huggingface.co/mlx-community/Qwen2.5-Coder-14B-Instruct-abliterated-4bit/resolve/main/model-00001-of-00002.safetensors",
            sha256: "d5e2...",
            estimatedSpeed: "~20 tok/s on M4",
            provider: .localTitanEngine(modelID: "qwen-2.5-14b-coder-abliterated-4bit"),
            draftModelID: "qwen-2.5-0.5b-instruct-4bit"
        ),

        ModelCatalog(
            id: "qwen-3.5-9b-4bit",
            author: "mlx-community",
            name: "Qwen 3.5 9B",
            size: "5.5 GB",
            quantization: "4-bit",
            minRAM: "12 GB",
            recommendedContext: "32K",
            downloadURL: "https://huggingface.co/mlx-community/Qwen3.5-9B-OptiQ-4bit/resolve/main/model-00001-of-00002.safetensors",
            sha256: "938d...",
            estimatedSpeed: "~50 tok/s on M4",
            provider: .localTitanEngine(modelID: "qwen-3.5-9b-4bit"),
            draftModelID: "qwen-3.5-0.8b-4bit"
        ),

        ModelCatalog(
            id: "qwen-2.5-7b-4bit",
            author: "mlx-community",
            name: "Qwen 2.5 7B",
            size: "4.2 GB",
            quantization: "4-bit",
            minRAM: "8 GB",
            recommendedContext: "8K",
            downloadURL: "https://huggingface.co/mlx-community/Qwen2.5-7B-Instruct-4bit/resolve/main/model.safetensors",
            sha256: "ea8f...",
            estimatedSpeed: "~45 tok/s on M4",
            provider: .localTitanEngine(modelID: "qwen-2.5-7b-4bit"),
            draftModelID: "qwen-2.5-0.5b-instruct-4bit"
        ),
        
        ModelCatalog(
            id: "gemma-4-e4b-it-4bit",
            author: "mlx-community",
            name: "Gemma 4 4B",
            size: "2.8 GB",
            quantization: "4-bit",
            minRAM: "8 GB",
            recommendedContext: "64K",
            downloadURL: "https://huggingface.co/mlx-community/gemma-4-e4b-it-4bit/resolve/main/model.safetensors",
            sha256: "339409bd18494955556e1fde6ccc15faaa9f707b911b74791fe290b9d722beed",
            estimatedSpeed: "~75 tok/s on M4",
            provider: .localTitanEngine(modelID: "gemma-4-e4b-it-4bit")
        ),
        
        ModelCatalog(
            id: "llama-3.1-8b-4bit",
            author: "mlx-community",
            name: "Llama 3.1 8B",
            size: "4.9 GB",
            quantization: "4-bit",
            minRAM: "16 GB",
            recommendedContext: "16K",
            downloadURL: "https://huggingface.co/mlx-community/Meta-Llama-3.1-8B-Instruct-4bit/resolve/main/model.safetensors",
            sha256: "b2c9...",
            estimatedSpeed: "~35 tok/s on M4",
            provider: .localTitanEngine(modelID: "llama-3.1-8b-4bit"),
            draftModelID: "llama-3.2-1b-instruct-4bit"
        ),
        
        // MARK: - CLOUD MODELS (OpenRouter)
        ModelCatalog(
            id: "gemini-2.0-flash",
            name: "Gemini 2.0 Flash",
            size: "N/A (Cloud)",
            quantization: "N/A",
            minRAM: "N/A",
            recommendedContext: "1M+",
            downloadURL: "",
            sha256: "",
            estimatedSpeed: "~120 tok/s",
            provider: .cloudOpenRouter(modelID: "google/gemini-2.0-flash-001")
        ),
        ModelCatalog(
            id: "claude-3.5-sonnet",
            name: "Claude 3.5 Sonnet",
            size: "N/A (Cloud)",
            quantization: "N/A",
            minRAM: "N/A",
            recommendedContext: "200K",
            downloadURL: "",
            sha256: "",
            estimatedSpeed: "~80 tok/s",
            provider: .cloudOpenRouter(modelID: "anthropic/claude-3.5-sonnet")
        )
    ]
}
