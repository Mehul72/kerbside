// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "SignVision",
    platforms: [.macOS(.v13), .iOS(.v16)],
    products: [
        .library(name: "SignVision", targets: ["SignVision"]),
        .executable(name: "signlook", targets: ["signlook"]),
    ],
    dependencies: [
        .package(path: "../SignKit")
    ],
    targets: [
        .target(name: "SignVision", dependencies: ["SignKit"]),
        // A development tool, not part of the app. Runs a real photograph
        // through the pipeline and prints the evidence behind each decision.
        .executableTarget(name: "signlook", dependencies: ["SignVision", "SignKit"]),
        .testTarget(name: "SignVisionTests", dependencies: ["SignVision"]),
    ]
)
