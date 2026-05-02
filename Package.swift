// swift-tools-version: 6.3
import PackageDescription

let package = Package(
    name: "EliteAgent",
    platforms: [
        .macOS("15.0") // Titan Engine Requirement: macOS 15 or later (M4/ANE Optimization)
    ],
    products: [
        .executable(name: "EliteAgent", targets: ["EliteAgent"]),
        .library(name: "EliteAgentCore", type: .static, targets: ["EliteAgentCore"]),
        .library(name: "CUNOSupport", targets: ["CUNOSupport"]),
        .library(name: "EliteAgentUI", targets: ["EliteAgentUI"]),
        .executable(name: "EliteAgentXPC", targets: ["EliteAgentXPC"]),
        .executable(name: "elite", targets: ["elite"]),
        .executable(name: "EliteService", targets: ["EliteService"]),
        .executable(name: "uma-bench", targets: ["uma-bench"]),
    ],
    dependencies: [
        .package(url: "https://github.com/ml-explore/mlx-swift", .upToNextMinor(from: "0.31.3")),
        .package(url: "https://github.com/ml-explore/mlx-swift-lm", .upToNextMinor(from: "3.31.3")),
        .package(url: "https://github.com/DePasqualeOrg/swift-tokenizers-mlx", from: "0.2.0"),
        .package(url: "https://github.com/DePasqualeOrg/swift-hf-api-mlx", from: "0.2.0"),

        .package(url: "https://github.com/trgysvc/audiointelligence.git", revision: "f9cc7195b04ce1077236bc77b905f797fafda0ce"),
        .package(url: "https://github.com/modelcontextprotocol/swift-sdk.git", revision: "a0ae212ebf6eab5f754c3129608bc5557637e605"),
        .package(url: "https://github.com/ibireme/yyjson.git", from: "0.12.0"),
        .package(url: "https://github.com/apple/swift-numerics.git", from: "1.1.0")
    ],
    targets: [
        .executableTarget(
            name: "EliteAgent",
            dependencies: [
                "EliteAgentCore",
                "EliteAgentUI",
                .product(name: "MLX", package: "mlx-swift"),

                .product(name: "AudioIntelligence", package: "audiointelligence"),
                .product(name: "Numerics", package: "swift-numerics")
            ],
            path: "Sources/EliteAgent"
        ),
        .target(
            name: "CUNOSupport",
            path: "Sources/CUNOSupport",
            publicHeadersPath: "include"
        ),
        .target(
            name: "EliteAgentCore",
            dependencies: [
                "CUNOSupport",
                .product(name: "MLX", package: "mlx-swift"),
                .product(name: "MLXRandom", package: "mlx-swift"),
                .product(name: "MLXNN", package: "mlx-swift"),
                .product(name: "MLXOptimizers", package: "mlx-swift"),
                .product(name: "MLXFast", package: "mlx-swift"),
                .product(name: "MLXLinalg", package: "mlx-swift"),
                .product(name: "MLXFFT", package: "mlx-swift"),
                .product(name: "MLXLLM", package: "mlx-swift-lm"),
                .product(name: "MLXLMCommon", package: "mlx-swift-lm"),
                .product(name: "MLXHuggingFace", package: "mlx-swift-lm"),
                .product(name: "MLXVLM", package: "mlx-swift-lm"),
                .product(name: "MLXEmbedders", package: "mlx-swift-lm"),
                .product(name: "MLXLMTokenizers", package: "swift-tokenizers-mlx"),
                .product(name: "MLXLMHFAPI", package: "swift-hf-api-mlx"),
                .product(name: "AudioIntelligence", package: "audiointelligence"),
                .product(name: "MCP", package: "swift-sdk"),
                .product(name: "yyjson", package: "yyjson"),
                .product(name: "Numerics", package: "swift-numerics")
            ],
            path: "Sources/EliteAgentCore",
            resources: [
                .process("UI/NeuralSight.metal"),
                .process("Resources/default.metallib")
            ],
            linkerSettings: []
        ),
        .target(
            name: "EliteAgentUI",
            dependencies: [
                "EliteAgentCore",
                .product(name: "MLX", package: "mlx-swift"),
                .product(name: "Numerics", package: "swift-numerics")
            ],
            path: "Sources/EliteAgentUI"
        ),
        .executableTarget(
            name: "EliteAgentXPC",
            dependencies: [
                "EliteAgentCore",
                "CUNOSupport",
                .product(name: "Numerics", package: "swift-numerics")
            ],
            path: "Sources/EliteAgentXPC"
        ),
        .executableTarget(
            name: "elite",
            dependencies: [
                "EliteAgentCore",
                .product(name: "MLX", package: "mlx-swift"),
                .product(name: "MLXLLM", package: "mlx-swift-lm"),
                .product(name: "Numerics", package: "swift-numerics")
            ],
            path: "Sources/elite"
        ),
        .testTarget(
            name: "EliteAgentTests",
            dependencies: ["EliteAgentCore", "CUNOSupport"],
            path: "Tests/EliteAgentTests"
        ),
        .executableTarget(
            name: "uma-bench",
            dependencies: [
                "EliteAgentCore",
                .product(name: "MLX", package: "mlx-swift"),
                .product(name: "Numerics", package: "swift-numerics")
            ],
            path: "Sources/uma-bench"
        ),
        .executableTarget(
            name: "EliteService",
            dependencies: [
                "EliteAgentCore",
                .product(name: "MLX", package: "mlx-swift"),
                .product(name: "MLXLLM", package: "mlx-swift-lm"),
                .product(name: "Numerics", package: "swift-numerics")
            ],
            path: "Sources/EliteService"
        )
    ]
)
