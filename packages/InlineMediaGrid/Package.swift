// swift-tools-version:5.5

import PackageDescription

let package = Package(
    name: "InlineMediaGrid",
    platforms: [.macOS(.v10_13)],
    products: [
        .library(name: "InlineMediaGrid", targets: ["InlineMediaGrid"]),
    ],
    dependencies: [
        .package(name: "TelegramCore", path: "../../submodules/telegram-ios/submodules/TelegramCore"),
        .package(name: "Postbox", path: "../../submodules/telegram-ios/submodules/Postbox"),
        .package(name: "SSignalKit", path: "../../submodules/telegram-ios/submodules/SSignalKit"),
        .package(name: "TelegramMediaPlayer", path: "../../submodules/telegram-ios/submodules/MediaPlayer"),
        .package(name: "TGUIKit", path: "../TGUIKit"),
        .package(name: "InlineStickerLayer", path: "../InlineStickerLayer"),
        .package(name: "TelegramMediaUtils", path: "../TelegramMediaUtils"),
        .package(name: "TelegramMedia", path: "../TelegramMedia"),
        .package(name: "ColorPalette", path: "../ColorPalette"),
        .package(name: "Localization", path: "../Localization"),
        .package(name: "InAppSettings", path: "../InAppSettings"),
        .package(name: "TelegramContext", path: "../TelegramContext"),
        .package(name: "TelegramTheme", path: "../TelegramTheme"),
        .package(name: "TelegramUtils", path: "../TelegramUtils"),
        .package(name: "MessageUtils", path: "../MessageUtils"),
        .package(name: "AvatarUI", path: "../AvatarUI"),
        .package(name: "GeneralRows", path: "../GeneralRows"),
        .package(name: "LocalAnimations", path: "../LocalAnimations"),
        .package(name: "ThemeSettings", path: "../ThemeSettings"),
        .package(name: "rnoise", path: "../../submodules/telegram-ios/third-party/rnnoise"),
    ],
    targets: [
        .target(
            name: "InlineMediaGrid",
            dependencies: [
                .product(name: "TelegramCore", package: "TelegramCore", condition: nil),
                .product(name: "Postbox", package: "Postbox", condition: nil),
                .product(name: "SwiftSignalKit", package: "SSignalKit", condition: nil),
                .product(name: "TelegramMediaPlayer", package: "TelegramMediaPlayer", condition: nil),
                .product(name: "TGUIKit", package: "TGUIKit", condition: nil),
                .product(name: "InlineStickerLayer", package: "InlineStickerLayer", condition: nil),
                .product(name: "TelegramMediaUtils", package: "TelegramMediaUtils", condition: nil),
                .product(name: "TelegramMedia", package: "TelegramMedia", condition: nil),
                .product(name: "ColorPalette", package: "ColorPalette", condition: nil),
                .product(name: "Localization", package: "Localization", condition: nil),
                .product(name: "InAppSettings", package: "InAppSettings", condition: nil),
                .product(name: "TelegramContext", package: "TelegramContext", condition: nil),
                .product(name: "TelegramTheme", package: "TelegramTheme", condition: nil),
                .product(name: "TelegramUtils", package: "TelegramUtils", condition: nil),
                .product(name: "MessageUtils", package: "MessageUtils", condition: nil),
                .product(name: "AvatarUI", package: "AvatarUI", condition: nil),
                .product(name: "GeneralRows", package: "GeneralRows", condition: nil),
                .product(name: "LocalAnimations", package: "LocalAnimations", condition: nil),
            ],
            path: "Sources/InlineMediaGrid"),
        .testTarget(
            name: "InlineMediaGridTests",
            dependencies: [
                "InlineMediaGrid",
                .product(name: "TGUIKit", package: "TGUIKit", condition: nil),
                .product(name: "TelegramTheme", package: "TelegramTheme", condition: nil),
                .product(name: "TelegramUtils", package: "TelegramUtils", condition: nil),
                .product(name: "GeneralRows", package: "GeneralRows", condition: nil),
                .product(name: "InAppSettings", package: "InAppSettings", condition: nil),
                .product(name: "TelegramCore", package: "TelegramCore", condition: nil),
                .product(name: "Postbox", package: "Postbox", condition: nil),
                .product(name: "ColorPalette", package: "ColorPalette", condition: nil),
                .product(name: "ThemeSettings", package: "ThemeSettings", condition: nil),
                .product(name: "rnoise", package: "rnoise", condition: nil),
            ],
            path: "Tests/InlineMediaGridTests"),
    ]
)
