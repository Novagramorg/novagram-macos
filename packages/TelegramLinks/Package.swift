// swift-tools-version:5.5

import PackageDescription

let package = Package(
    name: "TelegramLinks",
    platforms: [.macOS(.v10_13)],
    products: [.library(name: "TelegramLinks", targets: ["TelegramLinks"])],
    dependencies: [
        .package(name: "TelegramCore", path: "../../submodules/telegram-ios/submodules/TelegramCore"),
        .package(name: "Postbox", path: "../../submodules/telegram-ios/submodules/Postbox"),
        .package(name: "MtProtoKit", path: "../../submodules/telegram-ios/submodules/MtProtoKit"),
        .package(name: "Colors", path: "../Colors"),
        .package(name: "Strings", path: "../Strings"),
    ],
    targets: [
        .target(name: "TelegramLinks", dependencies: [
            .product(name: "TelegramCore", package: "TelegramCore"),
            .product(name: "Postbox", package: "Postbox"),
            .product(name: "MtProtoKit", package: "MtProtoKit"),
            .product(name: "Colors", package: "Colors"),
            .product(name: "Strings", package: "Strings"),
        ]),
        .testTarget(name: "TelegramLinksTests", dependencies: ["TelegramLinks"]),
    ]
)
