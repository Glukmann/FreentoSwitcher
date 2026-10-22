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
        .testTarget(
            name: "EngineTests",
            dependencies: ["Engine"],
            swiftSettings: [
                // swiftbuild schedules a standalone emit-module job that loses
                // the toolchain TestingMacros plugin path, breaking clean
                // builds of any file using @Test/@Suite. Point the compiler
                // at the plugin directory explicitly.
                .unsafeFlags([
                    "-plugin-path",
                    "/Library/Developer/CommandLineTools/usr/lib/swift/host/plugins/testing",
                ]),
            ]
        ),
    ]
)
