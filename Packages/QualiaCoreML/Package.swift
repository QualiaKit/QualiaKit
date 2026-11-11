// swift-tools-version: 5.9
import PackageDescription

// Preserve the local package entry point while compiling the root module only once.
let package = Package(
    name: "QualiaCoreML",
    platforms: [.iOS(.v16), .macOS(.v13)],
    // An explicit static product also avoids Xcode's duplicate automatic-product GUID.
    products: [.library(name: "QualiaCoreML", type: .static, targets: ["QualiaCoreMLCompatibility"])],
    dependencies: [.package(name: "QualiaKit", path: "../..")],
    targets: [
        .target(
            name: "QualiaCoreMLCompatibility",
            dependencies: [.product(name: "QualiaCoreML", package: "QualiaKit")]
        ),
        .testTarget(
            name: "QualiaCoreMLTests",
            dependencies: ["QualiaCoreMLCompatibility", .product(name: "QualiaKit", package: "QualiaKit")],
            resources: [.copy("Resources")]
        ),
    ]
)
