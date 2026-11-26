// swift-tools-version:6.0

import PackageDescription

let package = Package(
    name: "WalletEngine",
    platforms: [.macOS(.v10_13)],
    products: [
        .library(
            name: "WalletEngineFFI",
            targets: ["WalletEngineFFI"]),
    ],
    targets: [
        .binaryTarget(
            name: "wallet_engineFFI",
            path: "wallet_engineFFI.xcframework"
        ),
        .target(
            name: "WalletEngineFFI",
            dependencies: ["wallet_engineFFI"],
            swiftSettings: [
                .swiftLanguageMode(.v6),
            ],
            linkerSettings: [
                .linkedFramework("Foundation"),
                .linkedFramework("Security"),
            ]
        ),
        .testTarget(
            name: "WalletEngineFFITests",
            dependencies: ["WalletEngineFFI"]
        ),
    ]
)
