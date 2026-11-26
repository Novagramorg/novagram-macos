// swift-tools-version:5.5

import PackageDescription

let package = Package(
    name: "PhoneNumberUtils",
    platforms: [.macOS(.v10_13)],
    products: [
        .library(name: "PhoneNumberUtils", targets: ["PhoneNumberUtils"]),
    ],
    dependencies: [
        .package(name: "TelegramCore", path: "../../submodules/telegram-ios/submodules/TelegramCore"),
        .package(name: "libphonenumber", path: "../../submodules/telegram-ios/submodules/libphonenumber"),
        .package(name: "SSignalKit", path: "../../submodules/telegram-ios/submodules/SSignalKit"),
        .package(name: "TelegramContext", path: "../TelegramContext"),
    ],
    targets: [
        .target(
            name: "PhoneNumberUtils",
            dependencies: [
                .product(name: "TelegramCore", package: "TelegramCore", condition: nil),
                .product(name: "libphonenumber", package: "libphonenumber", condition: nil),
                .product(name: "SwiftSignalKit", package: "SSignalKit", condition: nil),
                .product(name: "TelegramContext", package: "TelegramContext", condition: nil),
            ],
            path: "Sources/PhoneNumberUtils"),
    ]
)
