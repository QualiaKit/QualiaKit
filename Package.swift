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
        // Text feedback and advanced model-agnostic sessions
        .library(
            name: "QualiaKit",
            targets: ["QualiaKit"]
        ),
        .library(
            name: "QualiaTesting",
            targets: ["QualiaTesting"]
        ),
        .library(
            name: "QualiaCoreML",
            targets: ["QualiaCoreML"]
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
        // Domain, analyzer, and injected haptic runtime.
        // It has no Core ML or external package dependencies.
        .target(
            name: "QualiaKit",
            path: "Sources/QualiaKit"
        ),
        .target(
            name: "QualiaTesting",
            dependencies: ["QualiaKit"],
            path: "Sources/QualiaTesting"
        ),
        .target(
            name: "QualiaCoreML",
            dependencies: ["QualiaKit"],
            path: "Packages/QualiaCoreML/Sources/QualiaCoreML"
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
            dependencies: ["QualiaKit", "QualiaTesting", "Qualia", "QualiaBert"],
            resources: [.copy("Resources")]
        ),
        .testTarget(
            name: "QualiaCoreMLTests",
            dependencies: ["QualiaCoreML", "QualiaKit"],
            path: "Packages/QualiaCoreML/Tests/QualiaCoreMLTests",
            resources: [.copy("Resources")]
        ),
    ]
)
