// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "nervoussystemprotect",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(
            name: "nervoussystemprotect",
            targets: ["nervoussystemprotect"]
        )
    ],
    dependencies: [
        .package(url: "https://github.com/ml-explore/mlx-swift", from: "0.10.0")
    ],
    targets: [
        .executableTarget(
            name: "nervoussystemprotect",
            dependencies: [
                .product(name: "MLX", package: "mlx-swift"),
                .product(name: "MLXNN", package: "mlx-swift"),
                .product(name: "MLXRandom", package: "mlx-swift"),
                .product(name: "MLXFFT", package: "mlx-swift")
            ],
            path: "Sources"
        )
    ]
)
