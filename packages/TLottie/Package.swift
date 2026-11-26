// swift-tools-version:5.5

import PackageDescription
import Foundation

let root = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent()
    .deletingLastPathComponent()
    .deletingLastPathComponent()

let library = root.appendingPathComponent("core-xprojects/tlottie/build").path
let headers = root.appendingPathComponent("submodules/tlottie/include").path

let package = Package(
    name: "TLottie",
    platforms: [.macOS(.v10_13)],
    products: [
        .library(name: "TLottie", targets: ["TLottie"]),
    ],
    targets: [
        .target(
            name: "TLottie",
            path: "Sources/TLottie",
            publicHeadersPath: "include",
            cSettings: [
                .unsafeFlags(["-I\(headers)"]),
            ],
            cxxSettings: [
                .unsafeFlags(["-I\(headers)"]),
            ],
            linkerSettings: [
                .unsafeFlags(["-L\(library)"]),
                .linkedLibrary("tlottie"),
                .linkedFramework("AppKit"),
            ]),
    ],
    cxxLanguageStandard: .gnucxx17
)
