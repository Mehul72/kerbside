// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "SignVision",
    platforms: [.macOS(.v13), .iOS(.v16)],
    products: [
        .library(name: "SignVision", targets: ["SignVision"])
    ],
    dependencies: [
        .package(path: "../SignKit")
    ],
    targets: [
        .target(name: "SignVision", dependencies: ["SignKit"]),
        .testTarget(name: "SignVisionTests", dependencies: ["SignVision"]),
    ]
)
