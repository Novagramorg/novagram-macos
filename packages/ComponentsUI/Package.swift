// swift-tools-version:5.5

import PackageDescription

let package = Package(
    name: "ComponentsUI",
    platforms: [.macOS(.v10_13)],
    products: [
        .library(name: "ComponentsUI", targets: ["ComponentsUI"]),
    ],
    dependencies: [
        .package(name: "TGUIKit", path: "../TGUIKit"),
    ],
    targets: [
        .target(
            name: "ComponentsUI",
            dependencies: [
                .product(name: "TGUIKit", package: "TGUIKit"),
            ],
            path: "Sources/ComponentsUI"),
    ]
)
