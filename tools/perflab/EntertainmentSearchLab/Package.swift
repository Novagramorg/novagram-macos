// swift-tools-version:5.5
import PackageDescription

let package = Package(
    name: "EntertainmentSearchLab",
    platforms: [.macOS(.v12)],
    dependencies: [
        .package(name: "SSignalKit", path: "../../../submodules/telegram-ios/submodules/SSignalKit"),
        .package(name: "Strings", path: "../../../packages/Strings")
    ],
    targets: [
        .target(name: "SearchLab", dependencies: [.product(name: "SwiftSignalKit", package: "SSignalKit"), .product(name: "Strings", package: "Strings")]),
        .executableTarget(name: "SearchBench", dependencies: ["SearchLab"]),
        .testTarget(name: "SearchLabTests", dependencies: ["SearchLab"])
    ]
)
