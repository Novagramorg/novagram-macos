// swift-tools-version:5.9
import PackageDescription
let package = Package(name: "ChatReplySwipeLab", platforms: [.macOS(.v10_15)], dependencies: [.package(path: "../../../packages/TGUIKit")], targets: [.testTarget(name: "SwipeTests", dependencies: ["TGUIKit"])])
