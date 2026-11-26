// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "RichTextEditorUI",
    platforms: [.macOS(.v10_13)],
    products: [
        .library(name: "RichTextEditorUI", targets: ["RichTextEditorUI"]),
    ],
    dependencies: [
        .package(name: "RichTextEditor", path: "../../submodules/telegram-ios/submodules/TelegramUI/Components/RichTextEditor"),
        .package(name: "SwiftMath", path: "../SwiftMath"),
    ],
    targets: [
        .target(
            name: "RichTextEditorUI",
            dependencies: [
                .product(name: "RichTextEditorCore", package: "RichTextEditor"),
                .product(name: "SwiftMath", package: "SwiftMath"),
            ]),
        .testTarget(
            name: "RichTextEditorUITests",
            dependencies: ["RichTextEditorUI"]),
    ]
)
