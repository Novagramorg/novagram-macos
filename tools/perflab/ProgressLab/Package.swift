// swift-tools-version:5.5

import PackageDescription

let package = Package(
    name: "ProgressLab",
    platforms: [.macOS(.v12)],
    dependencies: [
        .package(name: "TGUIKit", path: "../../../packages/TGUIKit"),
    ],
    targets: [
        .executableTarget(
            name: "ProgressLab",
            dependencies: [
                .product(name: "TGUIKit", package: "TGUIKit", condition: nil),
            ],
            path: "Sources/ProgressLab"),
    ]
)
