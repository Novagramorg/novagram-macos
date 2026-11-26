// swift-tools-version:5.9
import PackageDescription

let shared: [Target.Dependency] = ["TGUIKit", .product(name: "SwiftSignalKit", package: "SSignalKit")]

let package = Package(
    name: "AvatarTrackingLab",
    platforms: [.macOS(.v10_15)],
    dependencies: [
        .package(path: "../../../packages/TGUIKit"),
        .package(name: "SSignalKit", path: "../../../submodules/telegram-ios/submodules/SSignalKit")
    ],
    targets: [
        .target(name: "AvatarTrackingCurrent", dependencies: shared),
        .target(name: "AvatarTrackingOriginal", dependencies: shared),
        .testTarget(name: "AvatarTrackingTests", dependencies: ["AvatarTrackingCurrent", "AvatarTrackingOriginal", "TGUIKit"])
    ]
)
