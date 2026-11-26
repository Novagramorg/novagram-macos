// swift-tools-version:5.5

import PackageDescription

let common: [Target.Dependency] = [
    .product(name: "TGUIKit", package: "TGUIKit"),
    .product(name: "SwiftSignalKit", package: "SSignalKit"),
    .product(name: "TelegramCore", package: "TelegramCore"),
    .product(name: "Postbox", package: "Postbox"),
]

let package = Package(
    name: "AvatarUI",
    platforms: [.macOS(.v10_13)],
    products: [
        .library(name: "AvatarUI", targets: ["AvatarUI"]),
        .library(name: "AvatarUIShare", targets: ["AvatarUIShare"]),
    ],
    dependencies: [
        .package(name: "rnoise", path: "../../submodules/telegram-ios/third-party/rnnoise"),
        .package(name: "ColorPalette", path: "../ColorPalette"),
        .package(name: "TGUIKit", path: "../TGUIKit"),
        .package(name: "SSignalKit", path: "../../submodules/telegram-ios/submodules/SSignalKit"),
        .package(name: "TelegramCore", path: "../../submodules/telegram-ios/submodules/TelegramCore"),
        .package(name: "Postbox", path: "../../submodules/telegram-ios/submodules/Postbox"),
        .package(name: "TelegramUtils", path: "../TelegramUtils"),
        .package(name: "TelegramTheme", path: "../TelegramTheme"),
        .package(name: "TelegramContext", path: "../TelegramContext"),
    ],
    targets: [
        .target(
            name: "AvatarUI",
            dependencies: common + [
                .product(name: "TelegramTheme", package: "TelegramTheme"),
                .product(name: "TelegramContext", package: "TelegramContext"),
                .product(name: "TelegramUtils", package: "TelegramUtils"),
            ]),
        .target(
            name: "AvatarUIShare",
            dependencies: common + [
                .product(name: "TelegramThemeShare", package: "TelegramTheme"),
                .product(name: "TelegramUtilsShare", package: "TelegramUtils"),
            ],
            swiftSettings: [.define("SHARE")]),
        .testTarget(name: "AvatarUITests", dependencies: [
            "AvatarUI",
            .product(name: "rnoise", package: "rnoise"),
            .product(name: "TGUIKit", package: "TGUIKit"),
            .product(name: "ColorPalette", package: "ColorPalette"),
            .product(name: "Postbox", package: "Postbox"),
            .product(name: "TelegramCore", package: "TelegramCore"),
        ]),
    ]
)
