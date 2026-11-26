// swift-tools-version:5.5

import PackageDescription

let package = Package(
    name: "SecureIdUtils",
    platforms: [.macOS(.v10_13)],
    products: [
        .library(name: "SecureIdUtils", targets: ["SecureIdUtils"]),
    ],
    dependencies: [
        .package(name: "SSignalKit", path: "../../submodules/telegram-ios/submodules/SSignalKit"),
        .package(name: "TelegramCore", path: "../../submodules/telegram-ios/submodules/TelegramCore"),
        .package(name: "Postbox", path: "../../submodules/telegram-ios/submodules/Postbox"),
        .package(name: "Localization", path: "../Localization"),
        .package(name: "TelegramTheme", path: "../TelegramTheme"),
        .package(name: "TGPassportMRZ", path: "../TGPassportMRZ"),
    ],
    targets: [
        .target(
            name: "SecureIdUtils",
            dependencies: [
                .product(name: "SwiftSignalKit", package: "SSignalKit", condition: nil),
                .product(name: "TelegramCore", package: "TelegramCore", condition: nil),
                .product(name: "Postbox", package: "Postbox", condition: nil),
                .product(name: "Localization", package: "Localization", condition: nil),
                .product(name: "TelegramTheme", package: "TelegramTheme", condition: nil),
                .product(name: "TGPassportMRZ", package: "TGPassportMRZ", condition: nil),
            ],
            path: "Sources/SecureIdUtils"),
    ]
)
