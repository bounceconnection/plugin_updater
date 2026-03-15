// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "Pluginventory",
    platforms: [
        .macOS(.v14)
    ],
    targets: [
        .executableTarget(
            name: "Pluginventory",
            dependencies: [],
            path: "Pluginventory",
            resources: [
                .process("Resources")
            ]
        ),
        .testTarget(
            name: "PluginventoryTests",
            dependencies: ["Pluginventory"],
            path: "PluginventoryTests"
        )
    ]
)
