// swift-tools-version:5.5

import PackageDescription

let package = Package(
    name: "FoundationUtils",
    platforms: [.macOS(.v10_13)],
    products: [
        .library(
            name: "FoundationUtils",
            targets: ["FoundationUtils"]),
    ],
    dependencies: [
        .package(name: "SSignalKit", path: "../../submodules/telegram-ios/submodules/SSignalKit"),
        .package(name: "Strings", path: "../Strings"),
    ],
    targets: [
        .target(
            name: "FoundationUtils",
            dependencies: [
                .product(name: "SwiftSignalKit", package: "SSignalKit", condition: nil),
                .product(name: "Strings", package: "Strings", condition: nil)
            ]),
    ]
)
