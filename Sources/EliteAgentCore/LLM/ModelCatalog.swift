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
        provider: ModelProvider
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
    }
}

/// The authorized list of models for EliteAgent v9.0.
public struct ModelRegistry {
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
            provider: .localTitanEngine(modelID: "qwen-2.5-7b-coder-4bit")
        ),
        
        ModelCatalog(
            id: "qwen-3.5-7b-4bit",
            author: "mlx-community",
            name: "Qwen 3.5 7B",
            size: "4.5 GB",
            quantization: "4-bit",
            minRAM: "12 GB",
            recommendedContext: "32K",
            downloadURL: "https://huggingface.co/mlx-community/Qwen3.5-7B-Instruct-4bit/resolve/main/model.safetensors",
            sha256: "3f9a...", 
            estimatedSpeed: "~55 tok/s on M4",
            provider: .localTitanEngine(modelID: "qwen-3.5-7b-4bit")
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
            provider: .localTitanEngine(modelID: "qwen-2.5-7b-4bit")
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
            provider: .localTitanEngine(modelID: "llama-3.1-8b-4bit")
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
