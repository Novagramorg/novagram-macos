// swift-tools-version:5.5
import PackageDescription
let package = Package(name: "PeerRowTreeLab", platforms: [.macOS(.v10_15)], dependencies: [.package(path: "../../../packages/TGUIKit")], targets: [.target(name: "PeerRowTree", dependencies: ["TGUIKit"]), .testTarget(name: "PeerRowTreeTests", dependencies: ["PeerRowTree", "TGUIKit"])])
