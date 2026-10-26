// swift-tools-version:5.5

import PackageDescription

let package = Package(
    name: "FenixuzCore",
    platforms: [.macOS(.v10_13)],
    products: [
        .library(name: "FenixuzCore", targets: ["FenixuzCore"]),
        .library(name: "FenixuzShare", targets: ["FenixuzShare"])
    ],
    dependencies: [
        .package(name: "SSignalKit", path: "../../submodules/telegram-ios/submodules/SSignalKit"),
        .package(name: "TelegramCore", path: "../../submodules/telegram-ios/submodules/TelegramCore"),
        .package(name: "Postbox", path: "../../submodules/telegram-ios/submodules/Postbox"),
        .package(name: "TGUIKit", path: "../TGUIKit"),
        .package(name: "Localization", path: "../Localization"),
        .package(name: "AlertsUI", path: "../AlertsUI"),
        .package(name: "TelegramContext", path: "../TelegramContext")
    ],
    targets: [
        .target(
            name: "FenixuzShare",
            dependencies: [
                .product(name: "TelegramCore", package: "TelegramCore", condition: nil),
                .product(name: "Postbox", package: "Postbox", condition: nil),
                .product(name: "Localization", package: "Localization", condition: nil)
            ],
            path: "Sources/FenixuzShare"),
        .target(
            name: "FenixuzCore",
            dependencies: [
                .target(name: "FenixuzShare"),
                .product(name: "SwiftSignalKit", package: "SSignalKit", condition: nil),
                .product(name: "TelegramCore", package: "TelegramCore", condition: nil),
                .product(name: "Postbox", package: "Postbox", condition: nil),
                .product(name: "TGUIKit", package: "TGUIKit", condition: nil),
                .product(name: "Localization", package: "Localization", condition: nil),
                .product(name: "AlertsUI", package: "AlertsUI", condition: nil),
                .product(name: "TelegramContext", package: "TelegramContext", condition: nil)
            ],
            path: "Sources/FenixuzCore")
    ]
)
