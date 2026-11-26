// swift-tools-version:5.5

import PackageDescription

let package = Package(
    name: "LocalAnimations",
    platforms: [.macOS(.v10_13)],
    products: [
        .library(name: "LocalAnimations", targets: ["LocalAnimations"]),
    ],
    dependencies: [
        .package(name: "TelegramCore", path: "../../submodules/telegram-ios/submodules/TelegramCore"),
        .package(name: "Postbox", path: "../../submodules/telegram-ios/submodules/Postbox"),
        .package(name: "TelegramMedia", path: "../TelegramMedia"),
        .package(name: "TelegramMediaResources", path: "../TelegramMediaResources"),
        .package(name: "InAppSettings", path: "../InAppSettings"),
        .package(name: "TelegramUtils", path: "../TelegramUtils"),
        .package(name: "SSignalKit", path: "../../submodules/telegram-ios/submodules/SSignalKit"),
        .package(name: "TelegramContext", path: "../TelegramContext"),
        .package(name: "TelegramTheme", path: "../TelegramTheme"),
        .package(name: "TGUIKit", path: "../TGUIKit"),
    ],
    targets: [
        .target(
            name: "LocalAnimations",
            dependencies: [
                .product(name: "TelegramCore", package: "TelegramCore", condition: nil),
                .product(name: "Postbox", package: "Postbox", condition: nil),
                .product(name: "TelegramMedia", package: "TelegramMedia", condition: nil),
                .product(name: "TelegramMediaResources", package: "TelegramMediaResources", condition: nil),
                .product(name: "InAppSettings", package: "InAppSettings", condition: nil),
                .product(name: "TelegramUtils", package: "TelegramUtils", condition: nil),
                .product(name: "SwiftSignalKit", package: "SSignalKit", condition: nil),
                .product(name: "TelegramContext", package: "TelegramContext", condition: nil),
                .product(name: "TelegramTheme", package: "TelegramTheme", condition: nil),
                .product(name: "TGUIKit", package: "TGUIKit", condition: nil),
            ],
            path: "Sources/LocalAnimations"),
    ]
)
