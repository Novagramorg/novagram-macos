// swift-tools-version:5.5

import PackageDescription

let package = Package(
    name: "SceneEffects",
    platforms: [.macOS(.v10_13)],
    products: [
        .library(
            name: "SceneEffects",
            targets: ["SceneEffects"]),
    ],
    dependencies: [
        .package(name: "TGUIKit", path: "../TGUIKit"),
        .package(name: "TelegramMedia", path: "../TelegramMedia"),
        .package(name: "TelegramContext", path: "../TelegramContext"),
        .package(name: "TelegramMediaUtils", path: "../TelegramMediaUtils"),
        .package(name: "TelegramTheme", path: "../TelegramTheme"),
        .package(name: "InlineStickers", path: "../InlineStickers"),
        .package(name: "LocalAnimations", path: "../LocalAnimations"),
        .package(name: "TelegramUtils", path: "../TelegramUtils"),
        .package(name: "TelegramCore", path: "../../submodules/telegram-ios/submodules/TelegramCore"),
        .package(name: "Postbox", path: "../../submodules/telegram-ios/submodules/Postbox"),
        .package(name: "SSignalKit", path: "../../submodules/telegram-ios/submodules/SSignalKit"),
        .package(name: "MetalEngine", path: "../../submodules/telegram-ios/submodules/MetalEngine"),
        .package(name: "InlineStickerLayer", path: "../InlineStickerLayer"),
    ],
    targets: [
        .target(
            name: "SceneEffects",
            dependencies: [
                .product(name: "TGUIKit", package: "TGUIKit", condition: nil),
                .product(name: "SwiftSignalKit", package: "SSignalKit", condition: nil),
                .product(name: "MetalEngine", package: "MetalEngine", condition: nil),
                .product(name: "TelegramCore", package: "TelegramCore", condition: nil),
                .product(name: "TelegramMedia", package: "TelegramMedia", condition: nil),
                .product(name: "TelegramContext", package: "TelegramContext", condition: nil),
                .product(name: "TelegramMediaUtils", package: "TelegramMediaUtils", condition: nil),
                .product(name: "TelegramTheme", package: "TelegramTheme", condition: nil),
                .product(name: "InlineStickers", package: "InlineStickers", condition: nil),
                .product(name: "LocalAnimations", package: "LocalAnimations", condition: nil),
                .product(name: "TelegramUtils", package: "TelegramUtils", condition: nil),
                .product(name: "Postbox", package: "Postbox", condition: nil),
                .product(name: "InlineStickerLayer", package: "InlineStickerLayer", condition: nil),
            ],
            path: "Sources"),
    ]
)
