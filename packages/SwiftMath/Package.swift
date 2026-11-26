// swift-tools-version:5.5

import PackageDescription

let package = Package(
    name: "SwiftMath",
    platforms: [.macOS(.v10_13)],
    products: [
        .library(name: "SwiftMath", targets: ["SwiftMath"]),
    ],
    targets: [
        .target(
            name: "SwiftMath",
            path: "Sources/SwiftMath",
            resources: [
                .copy("Resources/latinmodern-math.otf"),
                .copy("Resources/latinmodern-math.plist")
            ]
        ),
    ]
)
