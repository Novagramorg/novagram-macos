// swift-tools-version:5.5

import PackageDescription

let package = Package(
    name: "ChatModeTypes",
    platforms: [.macOS(.v10_13)],
    products: [
        .library(name: "ChatModeTypes", targets: ["ChatModeTypes"]),
    ],
    dependencies: [
        .package(name: "SSignalKit", path: "../../submodules/telegram-ios/submodules/SSignalKit"),
        .package(name: "TelegramCore", path: "../../submodules/telegram-ios/submodules/TelegramCore"),
        .package(name: "Postbox", path: "../../submodules/telegram-ios/submodules/Postbox"),
        .package(name: "TGUIKit", path: "../TGUIKit"),
        .package(name: "Localization", path: "../Localization"),
        .package(name: "TelegramUtils", path: "../TelegramUtils"),
        .package(name: "InputView", path: "../InputView"),
        .package(name: "TelegramLinks", path: "../TelegramLinks"),
        .package(name: "InAppSettings", path: "../InAppSettings"),
        .package(name: "TelegramContext", path: "../TelegramContext"),
        .package(name: "TelegramTheme", path: "../TelegramTheme"),
    ],
    targets: [
        .target(
            name: "ChatModeTypes",
            dependencies: [
                .product(name: "SwiftSignalKit", package: "SSignalKit", condition: nil),
                .product(name: "TelegramCore", package: "TelegramCore", condition: nil),
                .product(name: "Postbox", package: "Postbox", condition: nil),
                .product(name: "TGUIKit", package: "TGUIKit", condition: nil),
                .product(name: "Localization", package: "Localization", condition: nil),
                .product(name: "TelegramUtils", package: "TelegramUtils", condition: nil),
                .product(name: "InputView", package: "InputView", condition: nil),
                .product(name: "TelegramLinks", package: "TelegramLinks", condition: nil),
                .product(name: "InAppSettings", package: "InAppSettings", condition: nil),
                .product(name: "TelegramContext", package: "TelegramContext", condition: nil),
                .product(name: "TelegramTheme", package: "TelegramTheme", condition: nil),
            ],
            path: "Sources/ChatModeTypes"),
    ]
)
