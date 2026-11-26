// swift-tools-version:5.9
import PackageDescription
let package = Package(name: "TextRunDrawingLab", platforms: [.macOS(.v10_15)], dependencies: [.package(path: "../../../packages/TGUIKit")], targets: [.executableTarget(name: "TextRunDrawingLab", dependencies: ["TGUIKit"])])
