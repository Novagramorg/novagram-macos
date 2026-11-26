// swift-tools-version:5.9
import PackageDescription
let package = Package(name: "ShimmerRenderLab", platforms: [.macOS(.v10_15)], dependencies: [.package(path: "../../../packages/TGUIKit"), .package(path: "TGUIKitBaseline")], targets: [.testTarget(name: "ShimmerTests", dependencies: ["TGUIKit", "TGUIKitBaseline"])])
