// swift-tools-version:5.9
import PackageDescription
let package = Package(name: "TableLayoutLab", platforms: [.macOS(.v10_15)], dependencies: [.package(path: "../../../packages/TGUIKit"), .package(path: "TGUIKitBaseline")], targets: [.testTarget(name: "LayoutTests", dependencies: ["TGUIKit", "TGUIKitBaseline"])])
