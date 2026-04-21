// swift-tools-version: 6.3.0
import PackageDescription

let package = Package(
    name: "EliteAgent",
    platforms: [
        .macOS("15.0") // Titan Engine Requirement: macOS 15 or later (M4/ANE Optimization)
    ],
    products: [
        .executable(name: "EliteAgent", targets: ["EliteAgent"]),
        .library(name: "EliteAgentCore", type: .dynamic, targets: ["EliteAgentCore"]),
        .library(name: "EliteAgentUI", targets: ["EliteAgentUI"]),
        .executable(name: "EliteAgentXPC", targets: ["EliteAgentXPC"]),
        .executable(name: "elite", targets: ["elite"]),
        .executable(name: "uma-bench", targets: ["uma-bench"]),
    ],
    dependencies: [
        .package(url: "https://github.com/ml-explore/mlx-swift", .upToNextMinor(from: "0.30.6")),
        .package(url: "https://github.com/ml-explore/mlx-swift-lm", .upToNextMinor(from: "2.30.6")),
        .package(url: "https://github.com/sparkle-project/Sparkle", from: "2.6.0"),
        .package(url: "https://github.com/trgysvc/audiointelligence.git", branch: "main")
    ],
    targets: [
        .executableTarget(
            name: "EliteAgent",
            dependencies: [
                "EliteAgentCore",
                "EliteAgentUI",
                .product(name: "MLX", package: "mlx-swift"),
                .product(name: "Sparkle", package: "Sparkle"),
                .product(name: "AudioIntelligence", package: "audiointelligence")
            ],
            path: "Sources/EliteAgent"
        ),
        .target(
            name: "EliteAgentCore",
            dependencies: [
                .product(name: "MLX", package: "mlx-swift"),
                .product(name: "MLXRandom", package: "mlx-swift"),
                .product(name: "MLXNN", package: "mlx-swift"),
                .product(name: "MLXOptimizers", package: "mlx-swift"),
                .product(name: "MLXFast", package: "mlx-swift"),
                .product(name: "MLXLinalg", package: "mlx-swift"),
                .product(name: "MLXLLM", package: "mlx-swift-lm"),
                .product(name: "MLXLMCommon", package: "mlx-swift-lm"),
                .product(name: "AudioIntelligence", package: "audiointelligence")
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
                .product(name: "MLX", package: "mlx-swift")
            ],
            path: "Sources/EliteAgentUI"
        ),
        .executableTarget(
            name: "EliteAgentXPC",
            dependencies: [
                "EliteAgentCore",
                .product(name: "MLX", package: "mlx-swift"),
                .product(name: "MLXLLM", package: "mlx-swift-lm")
            ],
            path: "Sources/EliteAgentXPC"
        ),
        .executableTarget(
            name: "elite",
            dependencies: [
                "EliteAgentCore",
                .product(name: "MLX", package: "mlx-swift"),
                .product(name: "MLXLLM", package: "mlx-swift-lm")
            ],
            path: "Sources/elite"
        ),
        .testTarget(
            name: "EliteAgentTests",
            dependencies: ["EliteAgentCore"],
            path: "Tests/EliteAgentTests"
        ),
        .executableTarget(
            name: "uma-bench",
            dependencies: [
                "EliteAgentCore",
                .product(name: "MLX", package: "mlx-swift")
            ],
            path: "Sources/uma-bench"
        )
    ]
)
