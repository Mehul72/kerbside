// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "SignKit",
    platforms: [.macOS(.v13), .iOS(.v16)],
    products: [
        .library(name: "SignKit", targets: ["SignKit"]),
        .executable(name: "signread", targets: ["signread"]),
    ],
    targets: [
        .target(name: "SignKit"),
        // A development tool, not part of the app. Lets a panel be read at the
        // command line without a simulator.
        .executableTarget(name: "signread", dependencies: ["SignKit"]),
        .testTarget(name: "SignKitTests", dependencies: ["SignKit"]),
    ]
)
