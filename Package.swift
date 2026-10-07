// swift-tools-version: 6.2

import PackageDescription

let package = Package(
    name: "golden-run",
    // VmnetNetwork (container networking for `pub get`) needs macOS 26.
    platforms: [.macOS("26.0")],
    products: [
        .executable(name: "golden-run", targets: ["golden-run"])
    ],
    dependencies: [
        // Pre-1.0: minor releases break API, so pin exactly and bump deliberately
        // together with Pins.vminitReference.
        .package(url: "https://github.com/apple/containerization.git", exact: "0.48.0"),
        .package(url: "https://github.com/apple/swift-argument-parser.git", from: "1.7.0"),
        .package(url: "https://github.com/apple/swift-system.git", from: "1.6.4"),
    ],
    targets: [
        .executableTarget(
            name: "golden-run",
            dependencies: [
                .product(name: "Containerization", package: "containerization"),
                .product(name: "ContainerizationOCI", package: "containerization"),
                .product(name: "ContainerizationOS", package: "containerization"),
                .product(name: "ContainerizationExtras", package: "containerization"),
                .product(name: "ContainerizationEXT4", package: "containerization"),
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
                .product(name: "SystemPackage", package: "swift-system"),
            ]
        )
    ]
)
