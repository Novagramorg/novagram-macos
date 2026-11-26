// swift-tools-version:5.5
import PackageDescription
let package = Package(name: "FoldingTextSplitLab", platforms: [.macOS(.v10_15)], targets: [.target(name: "TextSplit"), .testTarget(name: "TextSplitTests", dependencies: ["TextSplit"])])
