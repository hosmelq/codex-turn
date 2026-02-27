// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "CodexTurn",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(name: "CodexTurn", targets: ["CodexTurn"])
    ],
    dependencies: [
        .package(url: "https://github.com/sparkle-project/Sparkle.git", from: "2.0.0")
    ],
    targets: [
        .target(
            name: "CodexTurnCore",
            path: "Sources/CodexTurn"
        ),
        .executableTarget(
            name: "CodexTurn",
            dependencies: [
                "CodexTurnCore",
                .product(name: "Sparkle", package: "Sparkle")
            ],
            path: "Sources/CodexTurnApp",
            resources: [
                .copy("Resources/TopBarIcon.png")
            ]
        ),
        .testTarget(
            name: "CodexTurnTests",
            dependencies: ["CodexTurnCore"],
            path: "Tests/CodexTurnTests"
        )
    ]
)
