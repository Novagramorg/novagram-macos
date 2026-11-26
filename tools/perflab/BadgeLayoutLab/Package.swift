// swift-tools-version:5.9
import PackageDescription
let package = Package(name: "BadgeLayoutLab", platforms: [.macOS(.v10_15)], dependencies: [.package(path: "../../../packages/TGUIKit")], targets: [.target(name: "BadgeLab", dependencies: ["TGUIKit"]), .testTarget(name: "BadgeLabTests", dependencies: ["BadgeLab", "TGUIKit"])])
