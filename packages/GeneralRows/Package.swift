// swift-tools-version:5.5

import PackageDescription

let common: [Target.Dependency] = [
    .product(name: "TGUIKit", package: "TGUIKit", condition: nil),
    .product(name: "SwiftSignalKit", package: "SSignalKit", condition: nil),
    .product(name: "TelegramCore", package: "TelegramCore", condition: nil),
    .product(name: "Postbox", package: "Postbox", condition: nil),
    .product(name: "ColorPalette", package: "ColorPalette", condition: nil),
    .product(name: "InAppSettings", package: "InAppSettings", condition: nil),
    .product(name: "Localization", package: "Localization", condition: nil),
    .product(name: "TelegramIconsTheme", package: "TelegramIconsTheme", condition: nil),
]

let package = Package(
    name: "GeneralRows",
    platforms: [.macOS(.v10_13)],
    products: [
        .library(name: "GeneralRows", targets: ["GeneralRows"]),
        .library(name: "GeneralRowsShare", targets: ["GeneralRowsShare"]),
    ],
    dependencies: [
        .package(name: "TelegramIconsTheme", path: "../TelegramIconsTheme"),
        .package(name: "SSignalKit", path: "../../submodules/telegram-ios/submodules/SSignalKit"),
        .package(name: "TelegramCore", path: "../../submodules/telegram-ios/submodules/TelegramCore"),
        .package(name: "Postbox", path: "../../submodules/telegram-ios/submodules/Postbox"),
        .package(name: "TGUIKit", path: "../TGUIKit"),
        .package(name: "ColorPalette", path: "../ColorPalette"),
        .package(name: "TelegramTheme", path: "../TelegramTheme"),
        .package(name: "TelegramContext", path: "../TelegramContext"),
        .package(name: "TelegramUtils", path: "../TelegramUtils"),
        .package(name: "InAppSettings", path: "../InAppSettings"),
        .package(name: "Localization", path: "../Localization"),
        .package(name: "LocalAnimations", path: "../LocalAnimations"),
        .package(name: "rnoise", path: "../../submodules/telegram-ios/third-party/rnnoise"),
        .package(name: "ThemeSettings", path: "../ThemeSettings"),
        .package(name: "TelegramMedia", path: "../TelegramMedia"),
    ],
    targets: [
        .target(
            name: "GeneralRows",
            dependencies: common + [.product(name: "TelegramTheme", package: "TelegramTheme", condition: nil),
                                    .product(name: "TelegramContext", package: "TelegramContext", condition: nil),
                                    .product(name: "TelegramUtils", package: "TelegramUtils", condition: nil),
                                    .product(name: "LocalAnimations", package: "LocalAnimations", condition: nil),
                                    .product(name: "TelegramMedia", package: "TelegramMedia", condition: nil)],
            path: "Sources/GeneralRows"),
        .target(
            name: "GeneralRowsShare",
            dependencies: common + [.product(name: "TelegramThemeShare", package: "TelegramTheme", condition: nil),
                                    .product(name: "TelegramUtilsShare", package: "TelegramUtils", condition: nil)],
            path: "Sources/GeneralRowsShare",
            swiftSettings: [.define("SHARE")]),
        .testTarget(
            name: "GeneralRowsTests",
            dependencies: [
                "GeneralRows",
                .product(name: "TGUIKit", package: "TGUIKit", condition: nil),
                .product(name: "TelegramCore", package: "TelegramCore", condition: nil),
                .product(name: "Postbox", package: "Postbox", condition: nil),
                .product(name: "TelegramMedia", package: "TelegramMedia", condition: nil),
                .product(name: "TelegramContext", package: "TelegramContext", condition: nil),
                .product(name: "rnoise", package: "rnoise"),
                .product(name: "TelegramTheme", package: "TelegramTheme", condition: nil),
                .product(name: "ColorPalette", package: "ColorPalette", condition: nil),
                .product(name: "InAppSettings", package: "InAppSettings", condition: nil),
                .product(name: "ThemeSettings", package: "ThemeSettings", condition: nil)
            ]
        ),
    ]
)
