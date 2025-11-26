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
        .library(
            name: "QualiaKit",
            targets: ["QualiaKit"])
    ],
    targets: [
        .target(
            name: "QualiaKit",
            path: "src"
        )
    ]
)
