// swift-tools-version:5.5

import PackageDescription

let package = Package(
    name: "TelegramMediaResources",
    platforms: [.macOS(.v10_13)],
    products: [
        .library(
            name: "TelegramMediaResources",
            targets: ["TelegramMediaResources"]),
    ],
    dependencies: [
        .package(name: "Colors", path: "../Colors"),
        .package(name: "Postbox", path: "../../submodules/telegram-ios/submodules/Postbox"),
        .package(name: "SSignalKit", path: "../../submodules/telegram-ios/submodules/SSignalKit"),
        .package(name: "TelegramCore", path: "../../submodules/telegram-ios/submodules/TelegramCore")
    ],
    targets: [
        .target(
            name: "TelegramMediaResources",
            dependencies: [
                .product(name: "Colors", package: "Colors", condition: nil),
                .product(name: "Postbox", package: "Postbox", condition: nil),
                .product(name: "SwiftSignalKit", package: "SSignalKit", condition: nil),
                .product(name: "TelegramCore", package: "TelegramCore", condition: nil)
            ]),
    ]
)
