// swift-tools-version:5.5
import PackageDescription
let package = Package(name: "InlineReconciliationLab", platforms: [.macOS(.v10_15)], targets: [.target(name: "Reconciliation"), .testTarget(name: "ReconciliationTests", dependencies: ["Reconciliation"])])
