// swift-tools-version:5.9
import PackageDescription
let package = Package(name: "FrameTransitionLab", platforms: [.macOS(.v10_15)], dependencies: [.package(path: "../../../packages/TGUIKit"), .package(path: "TGUIKitBaseline")], targets: [.testTarget(name: "FrameTests", dependencies: ["TGUIKit", "TGUIKitBaseline"])])
