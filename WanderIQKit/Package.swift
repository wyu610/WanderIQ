// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "WanderIQKit",
    defaultLocalization: "en",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "WanderIQKit", targets: ["WanderIQKit"])
    ],
    targets: [
        .target(name: "WanderIQKit", resources: [.process("Resources")]),
        .testTarget(
            name: "WanderIQKitTests",
            dependencies: ["WanderIQKit"],
            resources: [.copy("Fixtures")]
        )
    ]
)
