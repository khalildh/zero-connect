// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "ZeroConnect",
    platforms: [
        .iOS(.v17),
        .macOS(.v14),
    ],
    products: [
        .library(
            name: "ZeroConnectCore",
            targets: ["ZeroConnectCore"]
        ),
    ],
    dependencies: [
        .package(url: "https://github.com/EthanLipnik/Loom.git", branch: "main"),
        // MeshtasticProtobufs lives inside Meshtastic-Apple as a subdirectory package.
        // For Stage 1, MeshtasticTransport uses raw BLE Data without protobuf encoding.
        // TODO: Add MeshtasticProtobufs as a local package or standalone fork for Stage 2.
    ],
    targets: [
        .target(
            name: "ZeroConnectCore",
            dependencies: [
                .product(name: "Loom", package: "Loom"),
            ],
            path: "Sources/ZeroConnectCore"
        ),
        .executableTarget(
            name: "ZeroConnectApp",
            dependencies: ["ZeroConnectCore"],
            path: "Sources/ZeroConnectApp"
        ),
        .testTarget(
            name: "ZeroConnectCoreTests",
            dependencies: ["ZeroConnectCore"],
            path: "Tests/ZeroConnectCoreTests"
        ),
    ]
)
