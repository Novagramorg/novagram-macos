// swift-tools-version:5.9
import PackageDescription
let package = Package(name: "StickerDecodeProbe", platforms: [.macOS(.v10_13)], targets: [.target(name: "DecodeReference"), .target(name: "DecodeCandidate"), .testTarget(name: "DecodeTests", dependencies: ["DecodeReference", "DecodeCandidate"])])
