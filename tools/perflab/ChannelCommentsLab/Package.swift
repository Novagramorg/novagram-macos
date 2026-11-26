// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "ChannelCommentsLab",
    platforms: [.macOS(.v10_15)],
    dependencies: [.package(path: "../../../packages/TGUIKit")],
    targets: [
        .target(name: "CommentsHarness", dependencies: ["TGUIKit"]),
        .testTarget(name: "CommentsTests", dependencies: ["CommentsHarness", "TGUIKit"])
    ]
)
