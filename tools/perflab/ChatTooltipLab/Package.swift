// swift-tools-version:5.5
import PackageDescription
let package = Package(name: "ChatTooltipLab", platforms: [.macOS(.v10_15)], dependencies: [.package(path: "../../../packages/TGUIKit"), .package(name: "SSignalKit", path: "../../../submodules/telegram-ios/submodules/SSignalKit")], targets: [.target(name: "TooltipRows", dependencies: ["TGUIKit", .product(name: "SwiftSignalKit", package: "SSignalKit")]), .testTarget(name: "TooltipTests", dependencies: ["TooltipRows"])])
