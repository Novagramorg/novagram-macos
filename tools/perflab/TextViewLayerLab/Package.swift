// swift-tools-version:5.5
import PackageDescription
let package = Package(name: "TextViewLayerLab", platforms: [.macOS(.v10_15)], dependencies: [.package(path: "../../../packages/TGUIKit")], targets: [.target(name: "ChatTextRows", dependencies: ["TGUIKit"]), .testTarget(name: "LayerTests", dependencies: ["TGUIKit", "ChatTextRows"])])
