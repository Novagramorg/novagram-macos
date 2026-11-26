// swift-tools-version:5.5
import PackageDescription
let package = Package(name: "MediaPlaybackLab", platforms: [.macOS(.v10_15)], dependencies: [.package(name: "SSignalKit", path: "../../../submodules/telegram-ios/submodules/SSignalKit")], targets: [.target(name: "Playback", dependencies: [.product(name: "SwiftSignalKit", package: "SSignalKit")]), .testTarget(name: "PlaybackTests", dependencies: ["Playback"])])
