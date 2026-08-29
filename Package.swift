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
        // QualiaKit 2.0: Model-agnostic domain and runtime contracts
        .library(
            name: "QualiaKit",
            targets: ["QualiaKit"]
        ),
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
        // QualiaKit 2.0 domain layer. It intentionally has no framework dependencies.
        .target(
            name: "QualiaKit",
            path: "Sources/QualiaKit"
        ),
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
            dependencies: ["QualiaKit", "Qualia", "QualiaBert"],
            resources: [.copy("Resources")]
        ),
    ]
)
