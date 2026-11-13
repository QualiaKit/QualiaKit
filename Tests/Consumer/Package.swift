// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "QualiaConsumerTests",
    platforms: [.iOS(.v16), .macOS(.v13)],
    dependencies: [.package(name: "QualiaKit", path: "../..")],
    targets: [
        .testTarget(name: "ConsumerTests", dependencies: [
            .product(name: "QualiaKit", package: "QualiaKit"),
            .product(name: "QualiaTesting", package: "QualiaKit"),
            .product(name: "QualiaCoreML", package: "QualiaKit"),
        ]),
    ]
)
