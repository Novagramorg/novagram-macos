// swift-tools-version:5.5

import PackageDescription

let dependencies: [Target.Dependency] = [
    .product(name: "TGUIKit", package: "TGUIKit", condition: nil),
    .product(name: "SwiftSignalKit", package: "SSignalKit", condition: nil),
    .product(name: "TelegramCore", package: "TelegramCore", condition: nil),
    .product(name: "Postbox", package: "Postbox", condition: nil),
    .product(name: "ColorPalette", package: "ColorPalette", condition: nil),
    .product(name: "ThemeSettings", package: "ThemeSettings", condition: nil),
    .product(name: "TelegramIconsTheme", package: "TelegramIconsTheme", condition: nil),
    .product(name: "InAppSettings", package: "InAppSettings", condition: nil),
    .product(name: "FoundationUtils", package: "FoundationUtils", condition: nil),
    .product(name: "Localization", package: "Localization", condition: nil),
    .product(name: "GZIP", package: "GZIP", condition: nil),
    .product(name: "Svg", package: "Svg", condition: nil),
    .product(name: "ApiCredentials", package: "ApiCredentials", condition: nil),
]

let package = Package(
    name: "TelegramTheme",
    platforms: [.macOS(.v10_13)],
    products: [
        .library(name: "TelegramTheme", targets: ["TelegramTheme"]),
        .library(name: "TelegramThemeShare", targets: ["TelegramThemeShare"]),
    ],
    dependencies: [
        .package(name: "SSignalKit", path: "../../submodules/telegram-ios/submodules/SSignalKit"),
        .package(name: "TelegramCore", path: "../../submodules/telegram-ios/submodules/TelegramCore"),
        .package(name: "Postbox", path: "../../submodules/telegram-ios/submodules/Postbox"),
        .package(name: "TGUIKit", path: "../TGUIKit"),
        .package(name: "ColorPalette", path: "../ColorPalette"),
        .package(name: "ThemeSettings", path: "../ThemeSettings"),
        .package(name: "TelegramIconsTheme", path: "../TelegramIconsTheme"),
        .package(name: "InAppSettings", path: "../InAppSettings"),
        .package(name: "FoundationUtils", path: "../FoundationUtils"),
        .package(name: "Localization", path: "../Localization"),
        .package(name: "GZIP", path: "../GZIP"),
        .package(name: "Svg", path: "../Svg"),
        .package(name: "ApiCredentials", path: "../ApiCredentials"),
    ],
    targets: [
        .target(
            name: "TelegramTheme",
            dependencies: dependencies,
            path: "Sources/TelegramTheme"),
        .target(
            name: "TelegramThemeShare",
            dependencies: dependencies,
            path: "Sources/TelegramThemeShare",
            swiftSettings: [.define("SHARE")]),
    ]
)
