// swift-tools-version: 6.3
import PackageDescription

let package = Package(
    name: "EliteAgent",
    platforms: [
        .macOS(.v14)
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
            dependencies: ["EliteAgentCore"],
            path: "Sources/EliteAgent",
            exclude: ["Resources"]
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
            path: "Sources/EliteAgentCore"
        ),
        .executableTarget(
            name: "EliteAgentXPC",
            dependencies: ["EliteAgentCore"],
            path: "Sources/EliteAgentXPC",
            exclude: ["Resources"]
        ),
        .executableTarget(
            name: "elite",
            dependencies: ["EliteAgentCore"],
            path: "Sources/elite"
        )
    ]
)
