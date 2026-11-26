// swift-tools-version:5.5

import PackageDescription

let package = Package(
    name: "CaptureExclusion",
    platforms: [.macOS(.v10_13)],
    products: [
        .library(name: "CaptureExclusion", targets: ["CaptureExclusion"]),
    ],
    dependencies: [
        .package(name: "ObjcUtils", path: "../ObjcUtils"),
    ],
    targets: [
        .target(
            name: "CaptureExclusion",
            dependencies: [
                .product(name: "ObjcUtils", package: "ObjcUtils", condition: nil),
            ],
            path: "Sources/CaptureExclusion"),
    ]
)
