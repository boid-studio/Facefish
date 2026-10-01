// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "RealityKitContent",
    platforms: [
        .iOS(.v18),
        .macOS(.v15),
        .visionOS(.v2),
    ],
    products: [
        .library(name: "RealityKitContent", targets: ["RealityKitContent"]),
    ],
    targets: [
        .target(name: "RealityKitContent"),
    ]
)