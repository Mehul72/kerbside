// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "ParkKit",
    platforms: [.macOS(.v13), .iOS(.v18)],
    products: [
        .library(name: "ParkKit", targets: ["ParkKit"]),
        .executable(name: "parkplan", targets: ["parkplan"]),
    ],
    dependencies: [
        .package(path: "../SignKit")
    ],
    targets: [
        .target(
            name: "ParkKit",
            dependencies: [.product(name: "SignKit", package: "SignKit")]
        ),
        // A development tool, not part of the app. Shows what a sign leaves a
        // car, and what would be scheduled, without a simulator.
        .executableTarget(name: "parkplan", dependencies: ["ParkKit"]),
        .testTarget(name: "ParkKitTests", dependencies: ["ParkKit"]),
    ]
)
