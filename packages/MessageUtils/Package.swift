// swift-tools-version:5.5

import PackageDescription

let package = Package(
    name: "MessageUtils",
    platforms: [.macOS(.v10_13)],
    products: [
        .library(name: "MessageUtils", targets: ["MessageUtils"]),
    ],
    dependencies: [
        .package(name: "SSignalKit", path: "../../submodules/telegram-ios/submodules/SSignalKit"),
        .package(name: "TelegramCore", path: "../../submodules/telegram-ios/submodules/TelegramCore"),
        .package(name: "Postbox", path: "../../submodules/telegram-ios/submodules/Postbox"),
        .package(name: "Localization", path: "../Localization"),
        .package(name: "TelegramTheme", path: "../TelegramTheme"),
        .package(name: "TelegramUtils", path: "../TelegramUtils"),
        .package(name: "InAppSettings", path: "../InAppSettings"),
        .package(name: "TelegramMediaUtils", path: "../TelegramMediaUtils"),
        .package(name: "ChatModeTypes", path: "../ChatModeTypes"),
        .package(name: "TelegramContext", path: "../TelegramContext"),
    ],
    targets: [
        .target(
            name: "MessageUtils",
            dependencies: [
                .product(name: "SwiftSignalKit", package: "SSignalKit", condition: nil),
                .product(name: "TelegramCore", package: "TelegramCore", condition: nil),
                .product(name: "Postbox", package: "Postbox", condition: nil),
                .product(name: "Localization", package: "Localization", condition: nil),
                .product(name: "TelegramTheme", package: "TelegramTheme", condition: nil),
                .product(name: "TelegramUtils", package: "TelegramUtils", condition: nil),
                .product(name: "InAppSettings", package: "InAppSettings", condition: nil),
                .product(name: "TelegramMediaUtils", package: "TelegramMediaUtils", condition: nil),
                .product(name: "ChatModeTypes", package: "ChatModeTypes", condition: nil),
                .product(name: "TelegramContext", package: "TelegramContext", condition: nil),
            ],
            path: "Sources/MessageUtils"),
    ]
)
