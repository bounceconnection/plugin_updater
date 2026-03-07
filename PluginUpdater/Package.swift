// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "PluginUpdater",
    platforms: [
        .macOS(.v14)
    ],
    targets: [
        .executableTarget(
            name: "PluginUpdater",
            dependencies: [],
            path: "PluginUpdater",
            resources: [
                .process("Resources")
            ]
        ),
        .testTarget(
            name: "PluginUpdaterTests",
            dependencies: ["PluginUpdater"],
            path: "PluginUpdaterTests"
        )
    ]
)
