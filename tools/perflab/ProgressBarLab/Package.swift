// swift-tools-version:5.5
import PackageDescription
let package = Package(name: "ProgressBarLab", platforms: [.macOS(.v10_15)], dependencies: [.package(path: "../../../packages/TGUIKit")], targets: [.target(name: "ProgressReference", dependencies: ["TGUIKit"]), .testTarget(name: "ProgressTests", dependencies: ["ProgressReference", "TGUIKit"])])
