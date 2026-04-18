// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "SoloScreen",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "SoloScreen",
            path: "Sources",
            resources: [
                .process("Resources")
            ],
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("AVFoundation"),
                .linkedFramework("ScreenCaptureKit"),
                .linkedFramework("NaturalLanguage"),
            ]
        ),
        .testTarget(
            name: "SoloScreenTests",
            dependencies: ["SoloScreen"],
            path: "Tests"
        ),
    ]
)
