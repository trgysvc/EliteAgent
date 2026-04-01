// swift-tools-version: 6.3
import PackageDescription

let package = Package(
    name: "EliteAgent",
    platforms: [
        .macOS("26.0") // Titan Engine Requirement: macOS 26 or later
    ],
    products: [
        .executable(name: "EliteAgent", targets: ["EliteAgent"]),
        .library(name: "EliteAgentCore", targets: ["EliteAgentCore"]),
        .executable(name: "EliteAgentXPC", targets: ["EliteAgentXPC"]),
        .executable(name: "elite", targets: ["elite"]),
    ],
    dependencies: [
        .package(path: "Packages/mlx-swift"),
        .package(url: "https://github.com/sparkle-project/Sparkle", from: "2.6.0")
    ],
    targets: [
        .executableTarget(
            name: "EliteAgent",
            dependencies: [
                "EliteAgentCore",
                .product(name: "MLX", package: "mlx-swift")
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
                .product(name: "Sparkle", package: "Sparkle")
            ],
            path: "Sources/EliteAgentCore",
            resources: [
                .process("UI/NeuralSight.metal")
            ],
            linkerSettings: [
                .unsafeFlags(["-Xlinker", "-no_warning_for_no_symbols"])
            ]
        ),
        .executableTarget(
            name: "EliteAgentXPC",
            dependencies: [
                "EliteAgentCore",
                .product(name: "MLX", package: "mlx-swift")
            ],
            path: "Sources/EliteAgentXPC"
        ),
        .executableTarget(
            name: "elite",
            dependencies: [
                "EliteAgentCore",
                .product(name: "MLX", package: "mlx-swift")
            ],
            path: "Sources/elite"
        )
    ]
)
