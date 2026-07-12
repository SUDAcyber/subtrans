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
    dependencies: [
        .package(url: "https://github.com/argmaxinc/WhisperKit.git", from: "1.0.0")
    ],
    targets: [
        .target(
            name: "SubtitleForgeCore"
        ),
        .executableTarget(
            name: "SubtitleForge",
            dependencies: [
                "SubtitleForgeCore",
                .product(name: "WhisperKit", package: "WhisperKit")
            ],
            resources: [
                .copy("Resources")
            ],
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
