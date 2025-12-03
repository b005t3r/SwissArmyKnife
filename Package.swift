// swift-tools-version: 6.1
// The swift-tools-version declares the minimum version of Swift required to build this package.

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
        // Products define the executables and libraries a package produces, making them visible to other packages.
        .library(
            name: "SwissArmyKnife",
            targets: ["SwissArmyKnife"]),
    ],
    targets: [
        // Targets are the basic building blocks of a package, defining a module or a test suite.
        // Targets can depend on other targets in this package and products from dependencies.
        .target(
            name: "SwissArmyKnife"),
    ]
)
