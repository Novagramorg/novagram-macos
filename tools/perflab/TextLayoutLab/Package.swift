// swift-tools-version:5.5
import PackageDescription
let package = Package(name: "TextLayoutLab", platforms: [.macOS(.v12)], targets: [
    .target(name: "Baseline"), .target(name: "Candidate"),
    .executableTarget(name: "LabRunner", dependencies: ["Baseline", "Candidate"]),
    .testTarget(name: "TextLayoutLabTests", dependencies: ["Baseline", "Candidate"])
])
