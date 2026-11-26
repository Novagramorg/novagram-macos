// swift-tools-version:5.5
import PackageDescription
let package = Package(name: "ShortPeerRowLab", platforms: [.macOS(.v10_15)], dependencies: [.package(path: "../../../packages/TGUIKit")], targets: [.target(name: "PeerRows", dependencies: ["TGUIKit"]), .testTarget(name: "PeerRowTests", dependencies: ["PeerRows"])])
