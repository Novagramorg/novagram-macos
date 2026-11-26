// swift-tools-version:5.5

import PackageDescription

let deps: [(String, String)] = [
    ("TelegramUtils", "../TelegramUtils"),
    ("TelegramMedia", "../TelegramMedia"),
    ("TelegramMediaResources", "../TelegramMediaResources"),
    ("InlineStickers", "../InlineStickers"),
    ("InputView", "../InputView"),
    ("TGUIKit", "../TGUIKit"),
    ("TelegramTheme", "../TelegramTheme"),
    ("TelegramContext", "../TelegramContext"),
    ("ColorPalette", "../ColorPalette"),
    ("LokiRng", "../../submodules/telegram-ios/submodules/Utils/LokiRng"),
]

let package = Package(
    name: "InlineStickerLayer",
    platforms: [.macOS(.v10_13)],
    products: [
        .library(name: "InlineStickerLayer", targets: ["InlineStickerLayer"]),
    ],
    dependencies: [
        .package(name: "SSignalKit", path: "../../submodules/telegram-ios/submodules/SSignalKit"),
        .package(name: "TelegramCore", path: "../../submodules/telegram-ios/submodules/TelegramCore"),
        .package(name: "Postbox", path: "../../submodules/telegram-ios/submodules/Postbox"),
    ] + deps.map { .package(name: $0.0, path: $0.1) },
    targets: [
        .target(
            name: "InlineStickerLayer",
            dependencies: [
                .product(name: "SwiftSignalKit", package: "SSignalKit", condition: nil),
                .product(name: "TelegramCore", package: "TelegramCore", condition: nil),
                .product(name: "Postbox", package: "Postbox", condition: nil),
            ] + deps.map { .product(name: $0.0, package: $0.0, condition: nil) },
            path: "Sources/InlineStickerLayer"),
    ]
)
