// swift-tools-version:5.5

import PackageDescription

let package = Package(
    name: "NovagramCore",
    platforms: [.macOS(.v10_13)],
    products: [
        .library(name: "NovagramCore", targets: ["NovagramCore"]),
        .library(name: "NovagramShare", targets: ["NovagramShare"])
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
        // NovagramServices SDK (private repo, release v1.1.0), macOS slice only. It holds the review
        // login endpoint, the demo phone and the Statistics API URL + key (masked), so none of them is
        // in this public repo. How to update it: NOVAGRAM_HOOKS.md, "NovagramServices SDK".
        .binaryTarget(
            name: "NovagramServices",
            path: "Frameworks/NovagramServices.xcframework"),
        .target(
            name: "NovagramShare",
            dependencies: [
                .product(name: "TelegramCore", package: "TelegramCore", condition: nil),
                .product(name: "Postbox", package: "Postbox", condition: nil),
                .product(name: "Localization", package: "Localization", condition: nil)
            ],
            path: "Sources/NovagramShare"),
        .target(
            name: "NovagramCore",
            dependencies: [
                .target(name: "NovagramShare"),
                .product(name: "SwiftSignalKit", package: "SSignalKit", condition: nil),
                .product(name: "TelegramCore", package: "TelegramCore", condition: nil),
                .product(name: "Postbox", package: "Postbox", condition: nil),
                .product(name: "TGUIKit", package: "TGUIKit", condition: nil),
                .product(name: "Localization", package: "Localization", condition: nil),
                .product(name: "AlertsUI", package: "AlertsUI", condition: nil),
                .product(name: "TelegramContext", package: "TelegramContext", condition: nil),
                .target(name: "NovagramServices")
            ],
            path: "Sources/NovagramCore")
    ]
)
