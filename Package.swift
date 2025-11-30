// swift-tools-version: 5.9
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "QualiaKit",
    platforms: [
        .iOS(.v16),
        .macOS(.v13),
    ],
    products: [
        // Qualia (Core): Lightweight, zero-dependency sentiment analysis with NLTagger
        .library(
            name: "Qualia",
            targets: ["Qualia"]
        ),
        // QualiaBert (Add-on): High-accuracy Russian sentiment via CoreML
        .library(
            name: "QualiaBert",
            targets: ["QualiaBert"]
        ),
    ],
    targets: [
        // Core target with haptics, NLTagger, and SwiftUI integration
        .target(
            name: "Qualia",
            path: "Sources/Qualia"
        ),
        // BERT-based sentiment provider (depends on Qualia)
        .target(
            name: "QualiaBert",
            dependencies: ["Qualia"],
            path: "Sources/QualiaBert"
        ),
        // Tests
        .testTarget(
            name: "QualiaKitTests",
            dependencies: ["Qualia", "QualiaBert"],
            resources: [.copy("Resources")]
        ),
    ]
)
