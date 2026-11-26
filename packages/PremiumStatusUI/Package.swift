// swift-tools-version:5.5

import PackageDescription

let package = Package(
    name: "PremiumStatusUI",
    platforms: [.macOS(.v10_13)],
    products: [
        .library(name: "PremiumStatusUI", targets: ["PremiumStatusUI"]),
    ],
    dependencies: [
        .package(name: "SSignalKit", path: "../../submodules/telegram-ios/submodules/SSignalKit"),
        .package(name: "TelegramCore", path: "../../submodules/telegram-ios/submodules/TelegramCore"),
        .package(name: "Postbox", path: "../../submodules/telegram-ios/submodules/Postbox"),
        .package(name: "TGUIKit", path: "../TGUIKit"),
        .package(name: "ColorPalette", path: "../ColorPalette"),
        .package(name: "Localization", path: "../Localization"),
        .package(name: "TelegramTheme", path: "../TelegramTheme"),
        .package(name: "TelegramContext", path: "../TelegramContext"),
        .package(name: "TelegramUtils", path: "../TelegramUtils"),
        .package(name: "InlineStickers", path: "../InlineStickers"),
        .package(name: "InAppSettings", path: "../InAppSettings"),
        .package(name: "LocalAnimations", path: "../LocalAnimations"),
        .package(name: "ObjcUtils", path: "../ObjcUtils"),
        .package(name: "TelegramMedia", path: "../TelegramMedia"),
        .package(name: "InlineStickerLayer", path: "../InlineStickerLayer"),
    ],
    targets: [
        .target(
            name: "PremiumStatusUI",
            dependencies: [
                .product(name: "SwiftSignalKit", package: "SSignalKit", condition: nil),
                .product(name: "TelegramCore", package: "TelegramCore", condition: nil),
                .product(name: "Postbox", package: "Postbox", condition: nil),
                .product(name: "TGUIKit", package: "TGUIKit", condition: nil),
                .product(name: "ColorPalette", package: "ColorPalette", condition: nil),
                .product(name: "Localization", package: "Localization", condition: nil),
                .product(name: "TelegramTheme", package: "TelegramTheme", condition: nil),
                .product(name: "TelegramContext", package: "TelegramContext", condition: nil),
                .product(name: "TelegramUtils", package: "TelegramUtils", condition: nil),
                .product(name: "InlineStickers", package: "InlineStickers", condition: nil),
                .product(name: "InAppSettings", package: "InAppSettings", condition: nil),
                .product(name: "LocalAnimations", package: "LocalAnimations", condition: nil),
                .product(name: "ObjcUtils", package: "ObjcUtils", condition: nil),
                .product(name: "TelegramMedia", package: "TelegramMedia", condition: nil),
                .product(name: "InlineStickerLayer", package: "InlineStickerLayer", condition: nil),
            ],
            path: "Sources/PremiumStatusUI"),
    ]
)
