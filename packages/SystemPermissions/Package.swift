// swift-tools-version:5.5

import PackageDescription

let package = Package(
    name: "SystemPermissions",
    platforms: [.macOS(.v10_13)],
    products: [
        .library(name: "SystemPermissions", targets: ["SystemPermissions"]),
    ],
    dependencies: [
        .package(name: "SSignalKit", path: "../../submodules/telegram-ios/submodules/SSignalKit"),
    ],
    targets: [
        .target(
            name: "SystemPermissions",
            dependencies: [
                .product(name: "SwiftSignalKit", package: "SSignalKit", condition: nil),
            ],
            path: "Sources/SystemPermissions"),
    ]
)
