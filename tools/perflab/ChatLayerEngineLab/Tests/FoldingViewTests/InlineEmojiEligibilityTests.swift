import Cocoa
import XCTest
import TGUIKit
import InputView
import InputTextView
import InlineStickerLayer
@testable import FoldingViewHarness
@testable import ChatLayerEngine

final class InlineEmojiEligibilityTests: XCTestCase {
    typealias Sticker = InlineStickerLayer.InlineStickerItem

    override func setUp() {
        TGUIKitTestBootstrap.install()
    }

    private func sticker(_ id: Int64 = 1) -> Sticker {
        Sticker(source: .attribute(ChatTextCustomEmojiAttribute(fileId: id)))
    }

    private func fixture(_ stickers: [Sticker], raw: Bool = true) -> FoldingViewHarness.FoldingTextLayout {
        let text = NSMutableAttributedString(string: "", attributes: nil)
        let attributes: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 18), .foregroundColor: NSColor.black]
        for sticker in stickers {
            let range = NSRange(location: text.length, length: 2)
            text.append(NSAttributedString(string: "🦆 ", attributes: attributes))
            text.addAttribute(TextInputAttributes.embedded, value: sticker, range: range)
            if raw, case let .attribute(source) = sticker.source {
                text.addAttribute(TextInputAttributes.customEmoji, value: TextInputTextCustomEmojiAttribute(fileId: source.fileId), range: range)
            }
        }
        let layout = FoldingViewHarness.FoldingTextLayout(attributedString: text, blocks: [TextViewLayout(text)], blockRanges: [NSRange(location: 0, length: text.length)], context: BlockContext(), revealed: [])
        layout.measure(width: 240)
        return layout
    }

    private func assertEligibility(_ layout: FoldingViewHarness.FoldingTextLayout, _ expected: Bool, _ label: String, file: StaticString = #filePath, line: UInt = #line) {
        let fast = ChatLayerMessageTextPresentation.simpleText(layout)
        let blocks = layout.blocks.map { InputTextView.FoldingTextLayout.ViewLayout(text: $0.text, isRevealed: $0.isRevealed, size: $0.size) }
        let full = ChatLayerMessageTextPresentation(InputTextView.FoldingTextLayout(blocks: blocks, appendingAnimation: layout.appendingAnimation))
        XCTAssertEqual(fast != nil, expected, label, file: file, line: line)
        XCTAssertEqual(ChatLayerMessageTextView.supports(full, hasRevealAction: true), expected, label, file: file, line: line)
        if expected, let fast {
            XCTAssertEqual(fast.blocks.count, full.blocks.count, label, file: file, line: line)
            XCTAssertEqual(fast.nativeFeatures, full.nativeFeatures, label, file: file, line: line)
        }
    }

    func testMalformedRawAndEmbeddedRunsRemainNativeInBothPreparations() throws {
        let mutations: [(String, (NSMutableAttributedString, NSRange) -> Void)] = [
            ("malformed raw", { $0.addAttribute(TextInputAttributes.customEmoji, value: NSNumber(value: 1), range: $1) }),
            ("wrong file id", { $0.addAttribute(TextInputAttributes.customEmoji, value: TextInputTextCustomEmojiAttribute(fileId: 99), range: $1) }),
            ("missing embedded", { $0.removeAttribute(TextInputAttributes.embedded, range: $1) }),
            ("malformed embedded", { $0.addAttribute(TextInputAttributes.embedded, value: "invalid" as NSString, range: $1) }),
            ("unmeasured equal source", { [self] in $0.addAttribute(TextInputAttributes.embedded, value: sticker(), range: $1) }),
            ("unmeasured avatar", { $0.addAttribute(TextInputAttributes.embedded, value: Sticker(source: .avatar(1)), range: $1) })
        ]
        for (label, mutate) in mutations {
            let layout = fixture([sticker(), sticker(2)])
            let text = try XCTUnwrap(layout.blocks.first?.text.attributedString as? NSMutableAttributedString)
            mutate(text, NSRange(location: 0, length: 2))
            assertEligibility(layout, false, label)
        }
    }

    func testEveryRawRunIsValidatedIncludingTrailingUnmeasuredRun() throws {
        let layout = fixture([sticker(), sticker(2)])
        let text = try XCTUnwrap(layout.blocks.first?.text.attributedString as? NSMutableAttributedString)
        let tail = NSRange(location: text.length - 1, length: 1)
        text.addAttribute(TextInputAttributes.customEmoji, value: TextInputTextCustomEmojiAttribute(fileId: 2), range: tail)
        text.addAttribute(TextInputAttributes.embedded, value: sticker(2), range: tail)
        assertEligibility(layout, false, "unmeasured trailing raw run")
    }

    func testDuplicateMeasuredIdentitiesAndSplitAttributeRunsRemainSupported() throws {
        let shared = sticker()
        let layout = fixture(Array(repeating: shared, count: 128))
        XCTAssertEqual(layout.blocks.first?.text.embeddedItems.count, 128)
        let text = try XCTUnwrap(layout.blocks.first?.text.attributedString as? NSMutableAttributedString)
        for index in stride(from: 0, to: text.length, by: 6) {
            text.addAttribute(.foregroundColor, value: NSColor.red, range: NSRange(location: index, length: 1))
        }
        assertEligibility(layout, true, "repeated measured identity and split runs")
        assertEligibility(fixture([sticker(), sticker()], raw: false), true, "measured source without raw metadata")
        assertEligibility(fixture((1...128).map { sticker(Int64($0)) }), true, "distinct measured identities")
    }
}
