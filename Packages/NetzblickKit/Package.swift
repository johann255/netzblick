// swift-tools-version:5.10
import PackageDescription

let package = Package(
    name: "NetzblickKit",
    defaultLocalization: "de",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "NetzblickKit", targets: ["NetzblickKit"])
    ],
    targets: [
        .target(
            name: "NetzblickKit",
            resources: [.process("Resources")],
            swiftSettings: [.enableExperimentalFeature("StrictConcurrency")]
        ),
        .testTarget(
            name: "NetzblickKitTests",
            dependencies: ["NetzblickKit"],
            resources: [.copy("Fixtures")]
        )
    ]
)
