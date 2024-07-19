// swift-tools-version: 5.9
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "swift-shared-kit",
    platforms: [
        .iOS(.v15),
        .macOS(.v13),
        .watchOS(.v9),
        .tvOS(.v16),
    ],
    products: [
        .library(name: "SharedKit", targets: ["SharedKit"]),
    ],
    targets: [
        .target(name: "SharedKit"),
        .testTarget(name: "SharedKitTests", dependencies: ["SharedKit"]),
    ]
)
