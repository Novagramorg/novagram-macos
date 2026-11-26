// swift-tools-version:5.5

import PackageDescription

let package = Package(
    name: "PerfLab",
    platforms: [.macOS(.v10_13)],
    products: [
        .library(name: "PerfLab", targets: ["PerfLab"]),
    ],
    targets: [
        .target(
            name: "PerfLab",
            path: "Sources/PerfLab"),
    ]
)
