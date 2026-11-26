// swift-tools-version:5.5
import PackageDescription

let package = Package(
    name: "PeerMediaProfileLab",
    platforms: [.macOS(.v10_13)],
    dependencies: [.package(name: "SSignalKit", path: "../../../submodules/telegram-ios/submodules/SSignalKit")],
    targets: [.executableTarget(name: "PeerMediaProfileLab", dependencies: [.product(name: "SwiftSignalKit", package: "SSignalKit")])]
)
