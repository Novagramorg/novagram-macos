// swift-tools-version:5.5
import PackageDescription
let package = Package(name: "PremiumStatusLab", platforms: [.macOS(.v10_15)], dependencies: [.package(name: "SSignalKit", path: "../../../submodules/telegram-ios/submodules/SSignalKit")], targets: [.target(name: "PeerObservationCore", dependencies: [.product(name: "SwiftSignalKit", package: "SSignalKit")], path: "Sources/Observation"), .testTarget(name: "ObservationTests", dependencies: ["PeerObservationCore"])])
