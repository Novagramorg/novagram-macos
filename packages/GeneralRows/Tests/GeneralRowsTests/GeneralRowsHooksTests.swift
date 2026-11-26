import XCTest
import AppKit
import TGUIKit
import TelegramCore
import Postbox
import TelegramMedia
import TelegramContext
@testable import GeneralRows

private final class StubInlineTextRenderer: InlineTextRenderer {
    func update(textView: TextView, layout: TextViewLayout, context: AccountContextProtocol, insetEmoji: CGFloat, emojiOffset: NSPoint, decreaseAvatar: CGFloat) {
    }
    func clear() {
    }
    func updateAnimatableContent(window: NSWindow?, isLite: Bool) {
    }
}

private final class StubAnimatedItemView: NSView, GeneralRowsAnimatedItemView {
    func updateAnimatedItem(context: AccountContextProtocol, file: TelegramMediaFile, size: NSSize, animated: Bool) {
    }
    func updateStickerHeader(with media: Media, size: NSSize, context: AccountContextProtocol, parent: Message?, table: TableView?, parameters: GeneralRowsStickerParameters?, animated: Bool, positionFlags: LayoutPositionFlags?, approximateSynchronousValue: Bool) {
    }
}

private final class StubStickerParameters: GeneralRowsStickerParameters {
    var colors: [LottieColor] = []
}

final class GeneralRowsHooksTests: XCTestCase {

    func testPlaceholderLinkAttributeUsesLinkKey() {
        let (key, value) = GeneralRowsHooks.placeholder.linkAttribute("https://telegram.org", { _ in })
        XCTAssertEqual(key, NSAttributedString.Key.link.rawValue)
        XCTAssertEqual(value as? String, "https://telegram.org")
    }

    func testPlaceholderDetectLinksLeavesStringUnchanged() {
        let string = NSMutableAttributedString(string: "https://telegram.org")
        GeneralRowsHooks.placeholder.detectLinks(string)
        XCTAssertEqual(string.string, "https://telegram.org")
    }

    func testPlaceholderRenderersAreUsable() {
        let renderer = GeneralRowsHooks.placeholder.makeInlineTextRenderer()
        renderer.clear()
        renderer.updateAnimatableContent(window: nil, isLite: false)
        XCTAssertNotNil(GeneralRowsHooks.placeholder.makeAnimatedItemView() as NSView)
    }

    func testInstallRoundTripsEveryHook() {
        var detected = false
        let executor = TextViewInteractions()
        GeneralRowsHooks.install(GeneralRowsHooks(linkExecutor: {
            return executor
        }, linkAttribute: { contents, _ in
            return ("custom.key", contents.uppercased())
        }, detectLinks: { _ in
            detected = true
        }, checkSelectedImage: { _, _ in
            return nil
        }, makeInlineTextRenderer: {
            return StubInlineTextRenderer()
        }, makeAnimatedItemView: {
            return StubAnimatedItemView(frame: .zero)
        }, makeStickerHeaderView: { frame in
            return StubAnimatedItemView(frame: frame)
        }, localStickerParameters: { _ in
            return StubStickerParameters()
        }))

        XCTAssertTrue(GeneralRowsHooks.isInstalled)
        XCTAssertTrue(GeneralRowsHooks.shared.linkExecutor() === executor)

        let (key, value) = GeneralRowsHooks.shared.linkAttribute("abc", { _ in })
        XCTAssertEqual(key, "custom.key")
        XCTAssertEqual(value as? String, "ABC")

        GeneralRowsHooks.shared.detectLinks(NSMutableAttributedString(string: ""))
        XCTAssertTrue(detected)

        XCTAssertNil(GeneralRowsHooks.shared.checkSelectedImage(.black, .white))
        XCTAssertTrue(GeneralRowsHooks.shared.makeInlineTextRenderer() is StubInlineTextRenderer)
        XCTAssertTrue(GeneralRowsHooks.shared.makeAnimatedItemView() is StubAnimatedItemView)
        XCTAssertTrue(GeneralRowsHooks.shared.makeStickerHeaderView(.zero) is StubAnimatedItemView)
    }
}
