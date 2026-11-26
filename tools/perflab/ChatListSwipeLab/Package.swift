// swift-tools-version:5.9
import PackageDescription
let package = Package(name: "ChatListSwipeLab", platforms: [.macOS(.v10_15)], dependencies: [.package(path: "../../../packages/TGUIKit")], targets: [.target(name: "SwipeLab", dependencies: ["TGUIKit"]), .testTarget(name: "SwipeLabTests", dependencies: ["SwipeLab", "TGUIKit"])])
