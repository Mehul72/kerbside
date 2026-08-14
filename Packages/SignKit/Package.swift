// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "SignKit",
    platforms: [.macOS(.v13), .iOS(.v16)],
    products: [
        .library(name: "SignKit", targets: ["SignKit"])
    ],
    targets: [
        .target(name: "SignKit"),
        .testTarget(name: "SignKitTests", dependencies: ["SignKit"]),
    ]
)
