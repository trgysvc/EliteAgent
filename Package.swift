// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "EliteAgent",
    platforms: [
        .macOS(.v26)
    ],
    products: [
        .executable(name: "EliteAgent", targets: ["EliteAgent"]),
        .library(name: "EliteAgentCore", targets: ["EliteAgentCore"]),
        .executable(name: "EliteAgentXPC", targets: ["EliteAgentXPC"]),
    ],
    dependencies: [
        .package(path: "Packages/mlx-swift")
    ],
    targets: [
        .executableTarget(
            name: "EliteAgent",
            dependencies: ["EliteAgentCore"],
            path: "Sources/EliteAgent"
        ),
        .target(
            name: "EliteAgentCore",
            dependencies: [
                .product(name: "MLX", package: "mlx-swift"),
                .product(name: "MLXRandom", package: "mlx-swift"),
                .product(name: "MLXNN", package: "mlx-swift"),
                .product(name: "MLXOptimizers", package: "mlx-swift")
            ],
            path: "Sources/EliteAgentCore"
        ),
        .executableTarget(
            name: "EliteAgentXPC",
            dependencies: ["EliteAgentCore"],
            path: "Sources/EliteAgentXPC"
        )
    ]
)
