// swift-tools-version:5.5
import PackageDescription

let package = Package(
    name: "MainAppLab",
    platforms: [.macOS(.v12)],
    dependencies: [.package(path: "../../../packages/Strings")],
    targets: [
        .target(name: "Production"),
        .target(name: "Baseline", dependencies: ["Strings"]),
        .executableTarget(name: "MainAppLab", dependencies: ["Production", "Baseline"]),
        .testTarget(name: "MainAppLabTests", dependencies: ["Production", "Baseline"])
    ]
)
