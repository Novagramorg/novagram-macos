// swift-tools-version:5.5

import PackageDescription

let package = Package(
    name: "FenixuzCore",
    platforms: [.macOS(.v10_13)],
    products: [
        .library(name: "FenixuzCore", targets: ["FenixuzCore"])
    ],
    dependencies: [
        .package(name: "Localization", path: "../Localization")
    ],
    targets: [
        .target(
            name: "FenixuzCore",
            dependencies: [
                .product(name: "Localization", package: "Localization", condition: nil)
            ],
            path: "Sources/FenixuzCore")
    ]
)
