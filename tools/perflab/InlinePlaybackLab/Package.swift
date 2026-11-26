// swift-tools-version:5.5
import PackageDescription
let package = Package(name: "InlinePlaybackLab", platforms: [.macOS(.v10_15)], dependencies: [.package(path: "../../../packages/TGUIKit")], targets: [.target(name: "Playback", dependencies: ["TGUIKit"]), .testTarget(name: "PlaybackTests", dependencies: ["Playback"])])
