// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "WPXRecorder",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(name: "WPXRecorder", targets: ["WPXRecorder"])
    ],
    targets: [
        .executableTarget(
            name: "WPXRecorder",
            path: "Sources/WPXRecorder"
        ),
        .testTarget(
            name: "WPXRecorderTests",
            dependencies: ["WPXRecorder"],
            path: "Tests/WPXRecorderTests"
        )
    ]
)
