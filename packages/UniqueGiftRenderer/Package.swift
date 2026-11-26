// swift-tools-version:5.5

import PackageDescription

let package = Package(
    name: "UniqueGiftRenderer",
    platforms: [.macOS(.v10_13)],
    products: [
        .library(name: "UniqueGiftRenderer", targets: ["UniqueGiftRenderer"]),
    ],
    dependencies: [
        .package(name: "LokiRng", path: "../../submodules/telegram-ios/submodules/Utils/LokiRng"),
    ],
    targets: [
        .target(
            name: "UniqueGiftRenderer",
            dependencies: [
                .product(name: "LokiRng", package: "LokiRng", condition: nil),
            ],
            path: "Sources/UniqueGiftRenderer"),
        .testTarget(
            name: "UniqueGiftRendererTests",
            dependencies: ["UniqueGiftRenderer"],
            path: "Tests/UniqueGiftRendererTests"),
    ]
)
