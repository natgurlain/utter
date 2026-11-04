// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "Utter",
    platforms: [.macOS(.v26)],
    targets: [
        // Pure, testable logic: gesture state machine, transcript assembly, locale choice.
        .target(
            name: "UtterCore",
            path: "Sources/UtterCore"
        ),
        // The menu bar app: hotkey, audio, Apple on-device speech, indicator, text insertion.
        .executableTarget(
            name: "Utter",
            dependencies: ["UtterCore"],
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
