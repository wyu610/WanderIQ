// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "PlanovaKit",
    defaultLocalization: "en",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "PlanovaKit", targets: ["PlanovaKit"])
    ],
    targets: [
        .target(name: "PlanovaKit", resources: [.process("Resources")]),
        .testTarget(name: "PlanovaKitTests", dependencies: ["PlanovaKit"])
    ]
)
