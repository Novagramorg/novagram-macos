// swift-tools-version:5.9
import PackageDescription
let package = Package(name: "ImageContentsLab", platforms: [.macOS(.v10_15)], dependencies: [.package(path: "../../../packages/TGUIKit"), .package(name: "SSignalKit", path: "../../../submodules/telegram-ios/submodules/SSignalKit")], targets: [.testTarget(name: "ImageContentsTests", dependencies: ["TGUIKit", .product(name: "SwiftSignalKit", package: "SSignalKit")])])
