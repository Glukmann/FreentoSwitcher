// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "FreentoSwitcher",
    platforms: [.macOS(.v14)],
    targets: [
        .target(name: "Engine"),
        .target(name: "Platform", dependencies: ["Engine"]),
        .executableTarget(
            name: "FreentoSwitcher",
            dependencies: ["Engine", "Platform"],
            path: "Sources/App"
        ),
        .testTarget(name: "EngineTests", dependencies: ["Engine"]),
    ]
)
