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
        .package(
            url: "https://github.com/Vatensa/GPUImage3.git",
            exact: "1.0.0"
        )
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
