// swift-tools-version:5.5

import PackageDescription

let package = Package(
    name: "ExternalVideoUtils",
    platforms: [.macOS(.v10_13)],
    products: [
        .library(name: "ExternalVideoUtils", targets: ["ExternalVideoUtils"]),
    ],
    dependencies: [
        .package(name: "SSignalKit", path: "../../submodules/telegram-ios/submodules/SSignalKit"),
        .package(name: "TelegramCore", path: "../../submodules/telegram-ios/submodules/TelegramCore"),
        .package(name: "Postbox", path: "../../submodules/telegram-ios/submodules/Postbox"),
        .package(name: "ObjcUtils", path: "../ObjcUtils"),
        .package(name: "InAppVideoServices", path: "../InAppVideoServices"),
        .package(name: "TGUIKit", path: "../TGUIKit"),
        .package(name: "TelegramTheme", path: "../TelegramTheme"),
    ],
    targets: [
        .target(
            name: "ExternalVideoUtils",
            dependencies: [
                .product(name: "SwiftSignalKit", package: "SSignalKit", condition: nil),
                .product(name: "TelegramCore", package: "TelegramCore", condition: nil),
                .product(name: "Postbox", package: "Postbox", condition: nil),
                .product(name: "ObjcUtils", package: "ObjcUtils", condition: nil),
                .product(name: "InAppVideoServices", package: "InAppVideoServices", condition: nil),
                .product(name: "TGUIKit", package: "TGUIKit", condition: nil),
                .product(name: "TelegramTheme", package: "TelegramTheme", condition: nil),
            ],
            path: "Sources/ExternalVideoUtils"),
    ]
)
