// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "AsyncTextLab",
    platforms: [.macOS(.v10_15)],
    dependencies: [.package(path: "../../../packages/TGUIKit")],
    targets: [
        .target(name: "AsyncTextHarness", dependencies: ["TGUIKit"]),
        .testTarget(name: "AsyncTextTests", dependencies: ["AsyncTextHarness", "TGUIKit"])
    ]
)
