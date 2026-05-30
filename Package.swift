// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "SubtitleForge",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .library(
            name: "SubtitleForgeCore",
            targets: ["SubtitleForgeCore"]
        ),
        .executable(
            name: "SubtitleForge",
            targets: ["SubtitleForge"]
        )
    ],
    targets: [
        .target(
            name: "SubtitleForgeCore"
        ),
        .executableTarget(
            name: "SubtitleForge",
            dependencies: ["SubtitleForgeCore"],
            linkerSettings: [
                .linkedFramework("Security")
            ]
        ),
        .testTarget(
            name: "SubtitleForgeCoreTests",
            dependencies: ["SubtitleForgeCore"]
        )
    ]
)
