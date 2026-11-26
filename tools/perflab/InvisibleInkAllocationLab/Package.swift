// swift-tools-version:5.5
import PackageDescription
let package = Package(name: "InvisibleInkAllocationLab", platforms: [.macOS(.v10_15)], dependencies: [.package(path: "../../../packages/TGUIKit")], targets: [.target(name: "OriginalInkDust", dependencies: ["TGUIKit"]), .testTarget(name: "InkDustTests", dependencies: ["TGUIKit", "OriginalInkDust"])])
