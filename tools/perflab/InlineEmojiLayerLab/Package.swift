// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "InlineEmojiLayerLab",
    platforms: [.macOS(.v10_15)],
    dependencies: [.package(path: "../../../packages/TGUIKit")],
    targets: [
        .target(name: "TelegramContext"),
        .target(name: "InputView"),
        .target(name: "InlineStickerLayer", dependencies: ["TGUIKit", "TelegramContext", "InputView"]),
        .target(name: "InlineEmojiHelper", dependencies: ["TGUIKit", "TelegramContext", "InputView", "InlineStickerLayer"]),
        .testTarget(name: "InlineEmojiTests", dependencies: ["InlineEmojiHelper", "TGUIKit", "TelegramContext", "InputView", "InlineStickerLayer"])
    ]
)
