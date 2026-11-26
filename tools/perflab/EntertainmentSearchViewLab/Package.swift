// swift-tools-version:5.5
import PackageDescription
let package = Package(
    name: "EntertainmentSearchViewLab",
    platforms: [.macOS(.v10_15)],
    dependencies: [.package(path: "../../../packages/TGUIKit")],
    targets: [
        .target(name: "SearchViews", dependencies: ["TGUIKit"]),
        .executableTarget(name: "SearchPreview", dependencies: ["SearchViews"]),
        .testTarget(name: "SearchViewsTests", dependencies: ["SearchViews"])
    ]
)
