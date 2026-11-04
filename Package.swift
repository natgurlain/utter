// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "Utter",
    platforms: [.macOS(.v26)],
    dependencies: [
        // Local open-model text cleanup (MLX on Apple silicon). Models are loaded
        // from disk only; nothing is downloaded by the app.
        .package(url: "https://github.com/ml-explore/mlx-swift-lm", .upToNextMinor(from: "3.32.3")),
        .package(url: "https://github.com/huggingface/swift-transformers", from: "1.3.0"),
    ],
    targets: [
        // Pure, testable logic: gesture state machine, transcript assembly, locale choice,
        // vocabulary matching and the cleanup prompt/guard.
        .target(
            name: "UtterCore",
            path: "Sources/UtterCore"
        ),
        // The menu bar app: hotkey, audio, Apple on-device speech, cleanup, indicator, text insertion.
        // Build it with scripts/build-app.sh (xcodebuild): SwiftPM alone can't compile MLX's Metal shaders.
        .executableTarget(
            name: "Utter",
            dependencies: [
                "UtterCore",
                .product(name: "MLXLLM", package: "mlx-swift-lm"),
                .product(name: "MLXLMCommon", package: "mlx-swift-lm"),
                .product(name: "Tokenizers", package: "swift-transformers"),
            ],
            path: "Sources/Utter",
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .testTarget(
            name: "UtterCoreTests",
            dependencies: ["UtterCore"],
            path: "Tests/UtterCoreTests"
        ),
    ]
)
