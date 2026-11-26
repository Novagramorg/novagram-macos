// swift-tools-version:5.5
import PackageDescription
let package = Package(
    name: "ControlNodeLab",
    platforms: [.macOS(.v10_15)],
    dependencies: [.package(path: "../../../packages/TGUIKit"), .package(name: "SSignalKit", path: "../../../submodules/telegram-ios/submodules/SSignalKit")],
    targets: [
        .target(name: "LabSupport", dependencies: ["TGUIKit"]),
        .target(name: "SceneLab", dependencies: ["TGUIKit", "LabSupport", .product(name: "SwiftSignalKit", package: "SSignalKit")]),
        .target(name: "SceneLabMutant", dependencies: ["TGUIKit", "LabSupport", .product(name: "SwiftSignalKit", package: "SSignalKit")]),
        .testTarget(name: "ControlNodeTests", dependencies: ["TGUIKit", "LabSupport", "SceneLab", "SceneLabMutant"])
    ]
)
