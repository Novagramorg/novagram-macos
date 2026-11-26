// swift-tools-version:5.5

import PackageDescription

let package = Package(
    name: "ArchiveUtils",
    platforms: [.macOS(.v10_13)],
    products: [
        .library(name: "ArchiveUtils", targets: ["ArchiveUtils"]),
    ],
    dependencies: [
        .package(name: "SSignalKit", path: "../../submodules/telegram-ios/submodules/SSignalKit"),
        .package(name: "Zip", path: "../../submodules/Zip"),
        .package(name: "TelegramMediaResources", path: "../TelegramMediaResources"),
    ],
    targets: [
        .target(
            name: "ArchiveUtils",
            dependencies: [
                .product(name: "SwiftSignalKit", package: "SSignalKit", condition: nil),
                .product(name: "Zip", package: "Zip", condition: nil),
                .product(name: "TelegramMediaResources", package: "TelegramMediaResources", condition: nil),
            ],
            path: "Sources/ArchiveUtils"),
    ]
)
