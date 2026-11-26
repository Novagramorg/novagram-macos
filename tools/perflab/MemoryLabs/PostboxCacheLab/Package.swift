// swift-tools-version:5.5
import PackageDescription
let package = Package(
    name: "PostboxLab",
    platforms: [.macOS(.v10_15)],
    dependencies: [
        .package(name: "Postbox", path: "../../../../submodules/telegram-ios/submodules/Postbox"),
        .package(name: "SSignalKit", path: "../../../../submodules/telegram-ios/submodules/SSignalKit"),
    ],
    targets: [
        .target(name: "PostboxLabSupport", dependencies: [.product(name: "Postbox", package: "Postbox"), .product(name: "SwiftSignalKit", package: "SSignalKit")]),
        .testTarget(name: "PostboxCacheLabTests", dependencies: ["PostboxLabSupport", .product(name: "Postbox", package: "Postbox"), .product(name: "SwiftSignalKit", package: "SSignalKit")]),
    ]
)
