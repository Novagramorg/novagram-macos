// swift-tools-version: 5.9
import PackageDescription

// NovagramAds SDK, dynamic xcframeworks (binary only, no SDK source here):
//   NovagramAds, NovagramInsights, NovagramInsightsUI. Ship all three from the same SDK build.
// Only the macos-arm64_x86_64 slice is kept in each (the iOS slices were removed, Info.plist updated to match).
// NovagramInsights and NovagramInsightsUI link NovagramAds at @rpath, and NovagramInsightsUI weak-links Charts
// itself, so the app target takes all three products and nothing else.
// Xcode embeds and signs them into Novagram.app (Contents/Frameworks).

let package = Package(
    name: "NovagramAds",
    platforms: [
        .macOS(.v10_15)
    ],
    products: [
        .library(name: "NovagramAds", targets: ["NovagramAds"]),
        .library(name: "NovagramInsights", targets: ["NovagramInsights"]),
        .library(name: "NovagramInsightsUI", targets: ["NovagramInsightsUI"])
    ],
    targets: [
        .binaryTarget(
            name: "NovagramAds",
            path: "NovagramAds.xcframework"
        ),
        .binaryTarget(
            name: "NovagramInsights",
            path: "NovagramInsights.xcframework"
        ),
        .binaryTarget(
            name: "NovagramInsightsUI",
            path: "NovagramInsightsUI.xcframework"
        )
    ]
)
