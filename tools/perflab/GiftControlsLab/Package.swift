// swift-tools-version:5.5
import PackageDescription
let package = Package(name: "GiftControlsLab", platforms: [.macOS(.v10_15)], dependencies: [.package(path: "../../../packages/TGUIKit")], targets: [.target(name: "GiftControls", dependencies: ["TGUIKit"]), .testTarget(name: "GiftControlsTests", dependencies: ["GiftControls"])])
