// swift-tools-version:5.5

import PackageDescription

let package = Package(
    name: "EmojiReplacements",
    platforms: [.macOS(.v10_13)],
    products: [
        .library(name: "EmojiReplacements", targets: ["EmojiReplacements"]),
    ],
    dependencies: [
        .package(name: "SSignalKit", path: "../../submodules/telegram-ios/submodules/SSignalKit"),
        .package(name: "Postbox", path: "../../submodules/telegram-ios/submodules/Postbox"),
        .package(name: "TGUIKit", path: "../TGUIKit"),
        .package(name: "Strings", path: "../Strings"),
    ],
    targets: [
        .target(
            name: "EmojiReplacements",
            dependencies: [
                .product(name: "SwiftSignalKit", package: "SSignalKit", condition: nil),
                .product(name: "Postbox", package: "Postbox", condition: nil),
                .product(name: "TGUIKit", package: "TGUIKit", condition: nil),
                .product(name: "Strings", package: "Strings", condition: nil),
            ],
            path: "Sources/EmojiReplacements"),
    ]
)
