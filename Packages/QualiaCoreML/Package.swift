// swift-tools-version: 5.9
import PackageDescription

// Stage 1 is additive: the root manifest is part of the immutable 0001 audit.
let package = Package(
    name: "QualiaCoreML",
    platforms: [.iOS(.v16), .macOS(.v13)],
    products: [.library(name: "QualiaCoreML", targets: ["QualiaCoreML"])],
    dependencies: [.package(name: "QualiaKit", path: "../..")],
    targets: [
        .target(name: "QualiaCoreML", dependencies: [.product(name: "QualiaKit", package: "QualiaKit")]),
        .testTarget(
            name: "QualiaCoreMLTests",
            dependencies: ["QualiaCoreML", .product(name: "QualiaKit", package: "QualiaKit")],
            resources: [.copy("Resources")]
        ),
    ]
)
