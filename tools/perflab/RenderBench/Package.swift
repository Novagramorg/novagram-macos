// swift-tools-version:5.5

import PackageDescription

let package = Package(
    name: "RenderBench",
    platforms: [.macOS(.v10_15)],
    dependencies: [
        .package(name: "TGUIKit", path: "../../../packages/TGUIKit"),
        .package(name: "SSignalKit", path: "../../../submodules/telegram-ios/submodules/SSignalKit"),
    ],
    targets: [
        .executableTarget(
            name: "RenderBench",
            dependencies: [
                .product(name: "TGUIKit", package: "TGUIKit", condition: nil),
                .product(name: "SwiftSignalKit", package: "SSignalKit", condition: nil),
            ],
            path: "Sources/RenderBench"),
    ]
)
