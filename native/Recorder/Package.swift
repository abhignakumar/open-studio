// swift-tools-version: 6.3
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "Recorder",
    platforms: [
        .macOS(.v14),
    ],
    targets: [
        .executableTarget(
            name: "Recorder"
        ),
        .testTarget(
            name: "RecorderTests",
            dependencies: ["Recorder"]
        ),
    ],
    swiftLanguageModes: [.v6]
)
