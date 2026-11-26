// swift-tools-version:5.9

import PackageDescription

let package = Package(
    name: "ChartLabMixed",
    platforms: [.macOS(.v14)],
    dependencies: [
        .package(name: "TGUIKit", path: "../../../../packages/TGUIKit"),
        .package(name: "SSignalKit", path: "../../../../submodules/telegram-ios/submodules/SSignalKit"),
    ],
    targets: [
        .target(
            name: "GraphCore",
            path: "Modules/GraphCore"),
        .target(
            name: "GraphUI",
            dependencies: [
                "GraphCore",
                .product(name: "TGUIKit", package: "TGUIKit", condition: nil),
                .product(name: "SwiftSignalKit", package: "SSignalKit", condition: nil),
            ],
            path: "Modules/GraphUI"),
        .executableTarget(
            name: "ChartLab",
            dependencies: [
                "GraphUI",
                "GraphCore",
                .product(name: "TGUIKit", package: "TGUIKit", condition: nil),
            ],
            path: "Modules/ChartLab"),
    ]
)
