// swift-tools-version:5.5
import PackageDescription
let package = Package(name: "StarsWidgetLab", platforms: [.macOS(.v10_15)], dependencies: [.package(path: "../../../packages/TGUIKit")], targets: [.target(name: "Effects", dependencies: ["TGUIKit"], resources: [.copy("Resources/star.png"), .copy("Resources/star@2x.png")]), .testTarget(name: "EffectsTests", dependencies: ["Effects", "TGUIKit"]), .executableTarget(name: "StarsWidgetProbe", dependencies: ["Effects", "TGUIKit"]), .executableTarget(name: "StarsWidgetRender", dependencies: ["Effects", "TGUIKit"])])
