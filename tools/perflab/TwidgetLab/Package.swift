// swift-tools-version:5.5
import PackageDescription

let package = Package(
    name: "TwidgetLab",
    platforms: [.macOS(.v10_15)],
    dependencies: [
        .package(name: "WidgetSandbox", path: "../../../third-party/widget-sandbox"),
        .package(name: "twidget", path: "../../../third-party/twidget"),
    ],
    targets: [
        .executableTarget(
            name: "TwidgetLab",
            dependencies: [.product(name: "WidgetSandbox", package: "WidgetSandbox"), .product(name: "LiteHTML", package: "twidget"), .product(name: "TwidgetRenderer", package: "twidget"), .product(name: "TwidgetIcons", package: "twidget"), .product(name: "Twidget3D", package: "twidget"), .product(name: "Twidget3DSandbox", package: "twidget"), .product(name: "WidgetSandboxProtocol", package: "WidgetSandbox")],
            path: "Sources/TwidgetLab"),
    ]
)
