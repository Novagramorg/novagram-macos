// swift-tools-version:5.5

import PackageDescription

let package = Package(
    name: "InputView",
    platforms: [.macOS(.v10_13)],
    products: [
        .library(
            name: "InputView",
            targets: ["InputView"]),
    ],
    dependencies: [
        .package(name: "TGUIKit", path: "../TGUIKit"),
        .package(name: "ColorPalette", path: "../ColorPalette"),
        .package(name: "Localization", path: "../Localization"),
        .package(name: "ObjcUtils", path: "../ObjcUtils"),
        .package(name: "Postbox", path: "../../submodules/telegram-ios/submodules/Postbox"),
        .package(name: "SSignalKit", path: "../../submodules/telegram-ios/submodules/SSignalKit"),
        .package(name: "TelegramCore", path: "../../submodules/telegram-ios/submodules/TelegramCore"),
    ],
    targets: [
        .target(
            name: "InputView",
            dependencies: [
                .product(name: "TGUIKit", package: "TGUIKit", condition: nil),
                .product(name: "Localization", package: "Localization", condition: nil),
                .product(name: "ColorPalette", package: "ColorPalette", condition: nil),
                .product(name: "ObjcUtils", package: "ObjcUtils", condition: nil),
                .product(name: "Postbox", package: "Postbox", condition: nil),
                .product(name: "SwiftSignalKit", package: "SSignalKit", condition: nil),
                .product(name: "TelegramCore", package: "TelegramCore", condition: nil),
            ]),
    ]
)
