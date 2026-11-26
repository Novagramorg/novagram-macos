// swift-tools-version:5.5
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "TextRecognizing",
    platforms: [.macOS(.v10_13)],
    products: [
        // Products define the executables and libraries a package produces, and make them visible to other packages.
        .library(
            name: "TextRecognizing",
            targets: ["TextRecognizing"]),
    ],
    dependencies: [
        // Dependencies declare other packages that this package depends on.
        // .package(url: /* package url */, from: "1.0.0"),
        .package(name: "SSignalKit", path: "../../submodules/telegram-ios/submodules/SSignalKit"),
        .package(name: "Postbox", path: "../../submodules/telegram-ios/submodules/Postbox"),
        .package(name: "TelegramCore", path: "../../submodules/telegram-ios/submodules/TelegramCore"),
        .package(name: "TGUIKit", path: "../TGUIKit"),
        .package(name: "Translate", path: "../Translate"),
        .package(name: "libwebp", path: "../../submodules/libwebp"),
        .package(name: "rnoise", path: "../../submodules/telegram-ios/third-party/rnnoise"),
    ],
    targets: [
        // Targets are the basic building blocks of a package. A target can define a module or a test suite.
        // Targets can depend on other targets in this package, and on products in packages this package depends on.
        .target(
            name: "TextRecognizing",
            dependencies: [.product(name: "SwiftSignalKit", package: "SSignalKit", condition: nil),
                           .product(name: "Translate", package: "Translate", condition: nil),
                           .product(name: "TGUIKit", package: "TGUIKit", condition: nil),
                           .product(name: "TelegramCore", package: "TelegramCore", condition: nil),
                           .product(name: "Postbox", package: "Postbox", condition: nil),
                           .product(name: "libwebp", package: "libwebp", condition: nil)]),
        .testTarget(
            name: "TextRecognizingTests",
            dependencies: [
                "TextRecognizing",
                .product(name: "SwiftSignalKit", package: "SSignalKit", condition: nil),
                .product(name: "TGUIKit", package: "TGUIKit", condition: nil),
                .product(name: "rnoise", package: "rnoise", condition: nil),
            ],
            path: "Tests/TextRecognizingTests"),
    ]
)
