import Cocoa
import XCTest
import TGUIKit
import InputTextView
@testable import FoldingBlocksHarness

final class InlineEmojiColorReuseTests: XCTestCase {
    override func setUp() { TGUIKitTestBootstrap.install() }

    private func layout(quoted: Bool, tint: NSColor?, textColor: NSColor = .black, fileId: Int64 = 101, fontSize: CGFloat = 16) -> FoldingTextLayout.ViewLayout {
        let value = NSMutableAttributedString(string: "🦆 hello مرحبا", attributes: [.font: NSFont.systemFont(ofSize: fontSize), .foregroundColor: textColor])
        let item = InlineStickerItem(.attribute(Emoji(fileId: fileId, color: tint)))
        value.addAttribute(TextInputAttributes.embedded, value: item, range: NSRange(location: 0, length: 2))
        if quoted {
            value.addAttribute(TextInputAttributes.quote, value: TextViewBlockQuoteData(id: 1, colors: .init(main: .blue)), range: value.range)
        }
        let text = TextViewLayout(value)
        text.measure(width: 240)
        return FoldingTextLayout.ViewLayout(text: text)
    }

    func testRepeatedExplicitTintKeepsExistingLayerAndOriginalTextColor() throws {
        for quoted in [false, true] {
            let block = makeCurrentBlock(quoted: quoted)
            let initial = layout(quoted: quoted, tint: .red)
            block.update(initial)
            let first = try XCTUnwrap(block.mediaLayers.first as? InlineStickerItemLayer)
            XCTAssertEqual(first.textColor, .black)
            for index in 0 ..< 8 {
                block.update(index % 2 == 0 ? initial : layout(quoted: quoted, tint: .red))
                XCTAssertEqual(block.mediaLayers.count, 1)
                XCTAssertTrue(block.mediaLayers.first === first, "quoted=\(quoted), update=\(index)")
                XCTAssertEqual(first.textColor, .black)
                XCTAssertTrue(first.superview === block.textView)
                XCTAssertTrue(first.superlayer === block.textView.embeddedContainer)
            }
        }
    }

    func testUnspecifiedAndMatchingTintsKeepExistingLayer() throws {
        for quoted in [false, true] {
            for tint: NSColor? in [nil, .black] {
                let block = makeCurrentBlock(quoted: quoted)
                block.update(layout(quoted: quoted, tint: tint))
                let first = try XCTUnwrap(block.mediaLayers.first as? InlineStickerItemLayer)
                block.update(layout(quoted: quoted, tint: tint))
                XCTAssertTrue(block.mediaLayers.first === first)
                XCTAssertEqual(first.textColor, .black)
            }
        }
    }

    func testExplicitTintEqualToTextColorDoesNotReuseUntintedLayer() throws {
        for quoted in [false, true] {
            let block = makeCurrentBlock(quoted: quoted)
            block.update(layout(quoted: quoted, tint: nil))
            var previous = try XCTUnwrap(block.mediaLayers.first as? InlineStickerItemLayer)
            XCTAssertNil(previous.color)
            for tint: NSColor? in [.black, nil, .black, nil] {
                block.update(layout(quoted: quoted, tint: tint))
                let current = try XCTUnwrap(block.mediaLayers.first as? InlineStickerItemLayer)
                XCTAssertEqual(block.mediaLayers.count, 1)
                XCTAssertFalse(current === previous)
                XCTAssertNil(previous.superlayer)
                XCTAssertEqual(current.textColor, .black)
                XCTAssertEqual(current.color, tint)
                block.update(layout(quoted: quoted, tint: tint))
                XCTAssertTrue(block.mediaLayers.first === current)
                previous = current
            }
        }
    }

    func testColorSourceAndGeometryChangesStillReplaceLayer() throws {
        for quoted in [false, true] {
            let block = makeCurrentBlock(quoted: quoted)
            block.update(layout(quoted: quoted, tint: .red))
            var previous = try XCTUnwrap(block.mediaLayers.first as? InlineStickerItemLayer)
            let changes: [(NSColor?, NSColor, Int64, CGFloat)] = [
                (.blue, .black, 101, 16),
                (.blue, .green, 101, 16),
                (.blue, .green, 102, 16),
                (.blue, .green, 102, 24),
                (nil, .green, 102, 24)
            ]
            for (tint, textColor, fileId, fontSize) in changes {
                block.update(layout(quoted: quoted, tint: tint, textColor: textColor, fileId: fileId, fontSize: fontSize))
                let current = try XCTUnwrap(block.mediaLayers.first as? InlineStickerItemLayer)
                XCTAssertEqual(block.mediaLayers.count, 1)
                XCTAssertFalse(current === previous)
                XCTAssertNil(previous.superlayer)
                XCTAssertEqual(current.textColor, textColor)
                XCTAssertTrue(current.superview === block.textView)
                previous = current
            }
        }
    }
}
