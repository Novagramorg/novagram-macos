// swift-tools-version:5.9
import PackageDescription
let package = Package(name: "StickerPathProbe", platforms: [.macOS(.v10_15)], targets: [.target(name: "PathReference"), .target(name: "PathCandidate"), .testTarget(name: "PathTests", dependencies: ["PathReference", "PathCandidate"])])
