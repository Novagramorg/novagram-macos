// swift-tools-version:5.5

import PackageDescription

let package = Package(
    name: "ChangePhoneNumberUI",
    platforms: [.macOS(.v10_13)],
    products: [
        .library(name: "ChangePhoneNumberUI", targets: ["ChangePhoneNumberUI"]),
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
        .package(name: "AlertsUI", path: "../AlertsUI"),
        .package(name: "TelegramMedia", path: "../TelegramMedia"),
        .package(name: "PhoneNumberUtils", path: "../PhoneNumberUtils"),
        .package(name: "LocalAnimations", path: "../LocalAnimations"),
        .package(name: "PhoneInputUI", path: "../PhoneInputUI"),
    ],
    targets: [
        .target(
            name: "ChangePhoneNumberUI",
            dependencies: [
                .product(name: "TGUIKit", package: "TGUIKit", condition: nil),
                .product(name: "SwiftSignalKit", package: "SSignalKit", condition: nil),
                .product(name: "TelegramCore", package: "TelegramCore", condition: nil),
                .product(name: "Postbox", package: "Postbox", condition: nil),
                .product(name: "ColorPalette", package: "ColorPalette", condition: nil),
                .product(name: "Localization", package: "Localization", condition: nil),
                .product(name: "TelegramTheme", package: "TelegramTheme", condition: nil),
                .product(name: "TelegramContext", package: "TelegramContext", condition: nil),
                .product(name: "TelegramUtils", package: "TelegramUtils", condition: nil),
                .product(name: "AlertsUI", package: "AlertsUI", condition: nil),
                .product(name: "TelegramMedia", package: "TelegramMedia", condition: nil),
                .product(name: "PhoneNumberUtils", package: "PhoneNumberUtils", condition: nil),
                .product(name: "LocalAnimations", package: "LocalAnimations", condition: nil),
                .product(name: "PhoneInputUI", package: "PhoneInputUI", condition: nil),
            ],
            path: "Sources/ChangePhoneNumberUI"),
    ]
)
