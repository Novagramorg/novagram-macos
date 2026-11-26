// swift-tools-version:5.5

import PackageDescription

let deps: [(String, String)] = [
    ("AlertsUI", "../AlertsUI"),
    ("ColorPalette", "../ColorPalette"),
    ("GeneralRows", "../GeneralRows"),
    ("InputDataUI", "../InputDataUI"),
    ("LocalAnimations", "../LocalAnimations"),
    ("Localization", "../Localization"),
    ("ShortPeerRow", "../ShortPeerRow"),
    ("TGUIKit", "../TGUIKit"),
    ("TelegramContext", "../TelegramContext"),
    ("TelegramIconsTheme", "../TelegramIconsTheme"),
    ("TelegramTheme", "../TelegramTheme"),
    ("TelegramUtils", "../TelegramUtils"),
]

let package = Package(
    name: "SelectPeersUI",
    platforms: [.macOS(.v10_13)],
    products: [
        .library(name: "SelectPeersUI", targets: ["SelectPeersUI"]),
    ],
    dependencies: [
        .package(name: "SSignalKit", path: "../../submodules/telegram-ios/submodules/SSignalKit"),
        .package(name: "TelegramCore", path: "../../submodules/telegram-ios/submodules/TelegramCore"),
        .package(name: "Postbox", path: "../../submodules/telegram-ios/submodules/Postbox"),
    ] + deps.map { .package(name: $0.0, path: $0.1) },
    targets: [
        .target(
            name: "SelectPeersUI",
            dependencies: [
                .product(name: "SwiftSignalKit", package: "SSignalKit", condition: nil),
                .product(name: "TelegramCore", package: "TelegramCore", condition: nil),
                .product(name: "Postbox", package: "Postbox", condition: nil),
            ] + deps.map { .product(name: $0.0, package: $0.0, condition: nil) },
            path: "Sources/SelectPeersUI"),
    ]
)
