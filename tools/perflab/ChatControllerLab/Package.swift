// swift-tools-version:5.5
import PackageDescription

let package = Package(
    name: "ChatControllerLab",
    platforms: [.macOS(.v12)],
    targets: [
        .target(name: "ScrollTypes"),
        .target(name: "LabCode", dependencies: ["ScrollTypes"]),
        .executableTarget(name: "ChatControllerLab", dependencies: ["LabCode"]),
        .testTarget(name: "ChatControllerLabTests", dependencies: ["LabCode"])
    ]
)
