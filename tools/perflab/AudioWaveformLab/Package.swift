// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "AudioWaveformLab",
    platforms: [.macOS(.v10_15)],
    dependencies: [.package(path: "../../../packages/TGUIKit")],
    targets: [
        .target(name: "WaveformCurrent", dependencies: ["TGUIKit"]),
        .target(name: "WaveformOriginal", dependencies: ["TGUIKit"]),
        .testTarget(name: "WaveformTests", dependencies: ["WaveformCurrent", "WaveformOriginal", "TGUIKit"])
    ]
)
