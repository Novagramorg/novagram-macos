// swift-tools-version:5.5
import PackageDescription
let package = Package(name: "ChatListActivityLab", platforms: [.macOS(.v10_15)], dependencies: [.package(path: "../../../packages/TGUIKit"), .package(name: "SSignalKit", path: "../../../submodules/telegram-ios/submodules/SSignalKit")], targets: [.target(name: "ActivityText", dependencies: ["TGUIKit", .product(name: "SwiftSignalKit", package: "SSignalKit")]), .testTarget(name: "ChatListActivityTests", dependencies: ["ActivityText", "TGUIKit"])])
