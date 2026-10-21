// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "QualiaDeveloperExamples",
    platforms: [.iOS(.v16), .macOS(.v13)],
    products: [.library(name: "QualiaExamples", targets: ["QualiaExamples"]),
               .executable(name: "qualia-walkthrough", targets: ["Walkthrough"])],
    dependencies: [.package(name: "QualiaKit", path: "../.."),
                   .package(name: "QualiaCoreML", path: "../../Packages/QualiaCoreML")],
    targets: [
        .target(name: "QualiaExamples", dependencies: [
            .product(name: "QualiaKit", package: "QualiaKit"),
            .product(name: "QualiaTesting", package: "QualiaKit"),
            .product(name: "QualiaCoreML", package: "QualiaCoreML")]),
        .executableTarget(name: "Walkthrough", dependencies: ["QualiaExamples", .product(name: "QualiaKit", package: "QualiaKit")]),
        .testTarget(name: "ConsumerTests", dependencies: ["QualiaExamples", .product(name: "QualiaKit", package: "QualiaKit"), .product(name: "QualiaTesting", package: "QualiaKit")]),
    ]
)
