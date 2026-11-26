// swift-tools-version:5.5
import PackageDescription
let package = Package(name: "ActivityPlaybackLab", platforms: [.macOS(.v10_15)], dependencies: [.package(path: "../../../packages/TGUIKit")], targets: [.target(name: "ActivityPlaybackCore", dependencies: ["TGUIKit"], path: "Sources/Activity"), .testTarget(name: "ActivityTests", dependencies: ["ActivityPlaybackCore", "TGUIKit"])])
