// swift-tools-version:5.5
import PackageDescription
let package = Package(name: "StarsEffectLab", platforms: [.macOS(.v10_15)], dependencies: [.package(path: "../../../packages/TGUIKit")], targets: [.target(name: "Effects", dependencies: ["TGUIKit"], resources: [.copy("Resources/particle.png")]), .testTarget(name: "EffectsTests", dependencies: ["Effects", "TGUIKit"]), .executableTarget(name: "StarsRenderLab", dependencies: ["Effects", "TGUIKit"])])
