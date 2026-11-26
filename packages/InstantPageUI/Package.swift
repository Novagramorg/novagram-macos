// swift-tools-version:5.5

import PackageDescription

let package = Package(
    name: "InstantPageUI",
    platforms: [.macOS(.v10_13)],
    products: [
        .library(name: "InstantPageUI", targets: ["InstantPageUI"]),
    ],
    dependencies: [
        .package(name: "SSignalKit", path: "../../submodules/telegram-ios/submodules/SSignalKit"),
        .package(name: "TelegramCore", path: "../../submodules/telegram-ios/submodules/TelegramCore"),
        .package(name: "Postbox", path: "../../submodules/telegram-ios/submodules/Postbox"),
        .package(name: "Emoji", path: "../../submodules/telegram-ios/submodules/Emoji"),
        .package(name: "TGUIKit", path: "../TGUIKit"),
        .package(name: "InputView", path: "../InputView"),
        .package(name: "ColorPalette", path: "../ColorPalette"),
        .package(name: "Localization", path: "../Localization"),
        .package(name: "TelegramTheme", path: "../TelegramTheme"),
        .package(name: "TelegramContext", path: "../TelegramContext"),
        .package(name: "TelegramMediaResources", path: "../TelegramMediaResources"),
        .package(name: "TelegramUtils", path: "../TelegramUtils"),
        .package(name: "MessageTextUtils", path: "../MessageTextUtils"),
        .package(name: "TelegramMedia", path: "../TelegramMedia"),
        .package(name: "TelegramMediaUtils", path: "../TelegramMediaUtils"),
        .package(name: "InAppSettings", path: "../InAppSettings"),
        .package(name: "AudioPlayerCore", path: "../AudioPlayerCore"),
        .package(name: "ObjcUtils", path: "../ObjcUtils"),
        .package(name: "RangeSet", path: "../../submodules/telegram-ios/submodules/Utils/RangeSet"),
        .package(name: "ChatModeTypes", path: "../ChatModeTypes"),
        .package(name: "InlineStickerLayer", path: "../InlineStickerLayer"),
        .package(name: "rnoise", path: "../../submodules/telegram-ios/third-party/rnnoise"),
    ],
    targets: [
        .target(
            name: "InstantPageUI",
            dependencies: [
                .product(name: "TGUIKit", package: "TGUIKit", condition: nil),
                .product(name: "InputView", package: "InputView", condition: nil),
                .product(name: "SwiftSignalKit", package: "SSignalKit", condition: nil),
                .product(name: "TelegramCore", package: "TelegramCore", condition: nil),
                .product(name: "Postbox", package: "Postbox", condition: nil),
                .product(name: "Emoji", package: "Emoji", condition: nil),
                .product(name: "ColorPalette", package: "ColorPalette", condition: nil),
                .product(name: "Localization", package: "Localization", condition: nil),
                .product(name: "TelegramTheme", package: "TelegramTheme", condition: nil),
                .product(name: "TelegramContext", package: "TelegramContext", condition: nil),
                .product(name: "TelegramMediaResources", package: "TelegramMediaResources", condition: nil),
                .product(name: "TelegramUtils", package: "TelegramUtils", condition: nil),
                .product(name: "MessageTextUtils", package: "MessageTextUtils", condition: nil),
                .product(name: "TelegramMedia", package: "TelegramMedia", condition: nil),
                .product(name: "TelegramMediaUtils", package: "TelegramMediaUtils", condition: nil),
                .product(name: "InAppSettings", package: "InAppSettings", condition: nil),
                .product(name: "AudioPlayerCore", package: "AudioPlayerCore", condition: nil),
                .product(name: "ObjcUtils", package: "ObjcUtils", condition: nil),
                .product(name: "RangeSet", package: "RangeSet", condition: nil),
                .product(name: "ChatModeTypes", package: "ChatModeTypes", condition: nil),
                .product(name: "InlineStickerLayer", package: "InlineStickerLayer", condition: nil),
            ],
            path: "Sources/InstantPageUI"),
        .testTarget(
            name: "InstantPageUITests",
            dependencies: [
                "InstantPageUI",
                .product(name: "MessageTextUtils", package: "MessageTextUtils", condition: nil),
                .product(name: "TelegramCore", package: "TelegramCore", condition: nil),
                .product(name: "Postbox", package: "Postbox", condition: nil),
                .product(name: "InAppSettings", package: "InAppSettings", condition: nil),
                .product(name: "rnoise", package: "rnoise", condition: nil),
            ],
            path: "Tests/InstantPageUITests"),
    ]
)
