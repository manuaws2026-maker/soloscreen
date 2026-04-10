// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "SubtleAI",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "SubtleAI",
            path: "Sources",
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("AVFoundation"),
                .linkedFramework("ScreenCaptureKit"),
                .linkedFramework("NaturalLanguage"),
            ]
        ),
        .testTarget(
            name: "SubtleAITests",
            dependencies: ["SubtleAI"],
            path: "Tests"
        ),
    ]
)
