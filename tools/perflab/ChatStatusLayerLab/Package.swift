// swift-tools-version:5.5
import PackageDescription
let package = Package(name: "ChatStatusLayerLab", platforms: [.macOS(.v10_15)], dependencies: [.package(path: "../../../packages/TGUIKit")], targets: [.target(name: "StatusLayers", dependencies: ["TGUIKit"]), .testTarget(name: "StatusLayerTests", dependencies: ["StatusLayers"])])
