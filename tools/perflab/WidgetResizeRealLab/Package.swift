// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "WidgetResizeRealLab",
    platforms: [.macOS(.v12)],
    dependencies: [
        .package(name: "TGUIKit", path: "../../../packages/TGUIKit"),
        .package(name: "twidget", path: "../../../third-party/twidget"),
        .package(name: "WidgetSandbox", path: "../../../third-party/widget-sandbox"),
    ],
    targets: [
        .executableTarget(
            name: "WidgetResizeRealLab",
            dependencies: [
                .product(name: "TGUIKit", package: "TGUIKit"),
                .product(name: "TwidgetRenderer", package: "twidget"),
                .product(name: "WidgetSandbox", package: "WidgetSandbox"),
            ],
            path: "Sources"),
    ]
)
