// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "ReactionPassiveLayerLab",
    platforms: [.macOS(.v10_15)],
    dependencies: [.package(path: "../../../packages/TGUIKit")],
    targets: [
        .target(name: "ReactionHarness", dependencies: ["TGUIKit"]),
        .testTarget(name: "ReactionTests", dependencies: ["ReactionHarness", "TGUIKit"])
    ]
)
