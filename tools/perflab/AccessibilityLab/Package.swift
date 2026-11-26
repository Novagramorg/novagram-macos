// swift-tools-version:5.5
import PackageDescription

let package = Package(
    name: "AccessibilityLab",
    platforms: [.macOS(.v12)],
    dependencies: [
        .package(name: "TGUIKit", path: "../../../packages/TGUIKit"),
    ],
    targets: [
        .executableTarget(
            name: "AccessibilityLab",
            dependencies: [
                .product(name: "TGUIKit", package: "TGUIKit"),
            ],
            path: "Sources"),
    ]
)
