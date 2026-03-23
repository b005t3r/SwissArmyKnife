// swift-tools-version: 6.1

import PackageDescription

let package = Package(
    name: "SwissArmyKnife",
    platforms: [
        .macOS(.v13),
        .iOS(.v15),
        .macCatalyst(.v15),
        .tvOS(.v14)
    ],
    products: [
        .library(
            name: "SwissArmyKnife",
            targets: ["SwissArmyKnife"]
        ),
    ],
    dependencies: [
        .package(name: "GPUImage", path: "../GPUImage3")
    ],
    targets: [
        .target(
            name: "SwissArmyKnife",
            dependencies: [
                .product(name: "GPUImage", package: "GPUImage")
            ]
        ),
    ]
)
