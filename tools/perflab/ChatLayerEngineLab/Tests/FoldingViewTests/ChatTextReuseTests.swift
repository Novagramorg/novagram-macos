import Cocoa
import XCTest
import TGUIKit
@testable import FoldingViewHarness

final class ChatTextReuseTests: XCTestCase {
    override func setUp() { TGUIKitTestBootstrap.install() }

    func item(_ id: Int, count: Int = 1, quoted: Bool = false, context: BlockContext, streaming: Bool = false, text: String? = nil, collapsable: Bool = false, linked: Bool = false) -> ChatMessageItem {
        let full = NSMutableAttributedString()
        var blocks: [TextViewLayout] = [], ranges: [NSRange] = []
        for index in 0..<count {
            let value = NSMutableAttributedString(string: text ?? "Message \(id), block \(index) مرحبا 👩🏽‍💻\n", attributes: [.font: NSFont.systemFont(ofSize: 14), .foregroundColor: NSColor.black])
            if quoted && index % 2 == 0 {
                value.addAttribute(TextInputAttributes.quote, value: TextViewBlockQuoteData(id: index, colors: .init(main: .blue), collapsable: collapsable), range: value.range)
            }
            if linked { value.addAttribute(.link, value: "https://example.com/\(id)/\(index)", range: NSRange(location: 0, length: min(4, value.length))) }
            ranges.append(NSRange(location: full.length, length: value.length))
            full.append(value)
            let block = TextViewLayout(value, disableTooltips: !linked)
            block.interactions.resolveLink = { $0 as? String }
            blocks.append(block)
        }
        let layout = FoldingTextLayout(attributedString: full, blocks: blocks, blockRanges: ranges, context: context, revealed: [], appendingAnimation: streaming)
        layout.measure(width: 240)
        return ChatMessageItem(id: id, layout: layout)
    }

    func testChangedContentKeepsContainerAndCompatibleBlocks() throws {
        for quoted in [false, true] {
            let context = BlockContext(), row = ReusedChatTextRow(frame: .zero)
            row.bind(item(1, count: 3, quoted: quoted, context: context))
            let view = try XCTUnwrap(row.text), blocks = view.textViews
            let next = item(2, count: 3, quoted: quoted, context: context)
            next.textOrigin = NSPoint(x: 17, y: 94)
            row.bind(next)
            XCTAssertTrue(row.text === view)
            XCTAssertTrue(zip(blocks, view.textViews).allSatisfy { $0 === $1 })
            XCTAssertEqual(view.frame, row.textFrame(next))
            XCTAssertEqual(view.textViews.map { $0.textLayout?.attributedString.string }, next.textLayout.blocks.map { $0.text.attributedString.string })
            XCTAssertEqual(row.subviews.count, 1)
        }
    }

    func testSameStringDifferentMessageClearsSelectionWithoutChangingOldSnapshot() throws {
        let context = BlockContext(), row = ReusedChatTextRow(frame: .zero)
        let old = item(1, context: context, text: "Same message")
        row.bind(old)
        old.textLayout.blocks[0].text.selectedRange.range = NSRange(location: 0, length: 4)
        let view = try XCTUnwrap(row.text)
        let next = item(2, context: context, text: "Same message")
        row.bind(next)
        XCTAssertTrue(row.text === view)
        XCTAssertEqual(next.textLayout.blocks[0].text.selectedRange.range.location, NSNotFound)
        XCTAssertEqual(old.textLayout.blocks[0].text.selectedRange.range, NSRange(location: 0, length: 4))
        let baseline = ReplacementChatTextRow(frame: .zero)
        baseline.bind(old)
        let baselineNext = item(2, context: context, text: "Same message")
        baseline.bind(baselineNext)
        XCTAssertEqual(baselineNext.textLayout.blocks[0].text.selectedRange.range, NSRange(location: 0, length: 4))
    }

    func testSameMessageSameTextPreservesSelection() {
        let context = BlockContext(), row = ReusedChatTextRow(frame: .zero)
        let old = item(1, context: context)
        row.bind(old)
        old.textLayout.blocks[0].text.selectedRange.range = NSRange(location: 1, length: 4)
        let next = item(1, context: context)
        row.bind(next)
        XCTAssertEqual(next.textLayout.blocks[0].text.selectedRange.range, NSRange(location: 1, length: 4))
    }

    func testFallbackPreservesOldViewForActivePressAnimationAndAccountChange() throws {
        for reason in 0..<5 {
            let context = BlockContext(), row = ReusedChatTextRow(frame: .zero)
            row.bind(item(1, context: context, streaming: reason == 4))
            let view = try XCTUnwrap(row.text), text = try XCTUnwrap(view.textViews.first)
            if reason == 0 { text.controlState = .Highlight }
            if reason == 1 { text.canBeResponder = false }
            if reason == 2 {
                let animation = CABasicAnimation(keyPath: "opacity")
                animation.fromValue = 0; animation.toValue = 1; animation.duration = 20
                view.layer?.add(animation, forKey: "test")
            }
            let next = item(2, context: reason == 3 ? BlockContext() : context)
            row.bind(next)
            XCTAssertFalse(row.text === view, "reason=\(reason)")
            XCTAssertNil(view.superview)
        }
    }

    func testAnimatedReplacementAndStreamingKeepTheirOriginalPaths() throws {
        let context = BlockContext(), row = ReusedChatTextRow(frame: .zero)
        row.bind(item(1, context: context))
        let original = try XCTUnwrap(row.text)
        row.bind(item(2, context: context), animated: true)
        XCTAssertFalse(row.text === original)
        row.bind(item(3, context: context, streaming: true))
        let streaming = try XCTUnwrap(row.text), dots = try XCTUnwrap(streaming.appendingAnimationView)
        row.bind(item(4, context: context, streaming: true))
        XCTAssertFalse(row.text === streaming)
        XCTAssertTrue(row.text?.appendingAnimationView === dots)
        XCTAssertNil(streaming.appendingAnimationView)
    }

    func testCallbacksUseNewMessageAndPapercutRemovesText() throws {
        let context = BlockContext(), row = ReusedChatTextRow(frame: .zero)
        let old = item(1, context: context), next = item(2, quoted: true, context: context)
        row.bind(old)
        let view = try XCTUnwrap(row.text)
        row.bind(next)
        view.revealBlockAtIndex?(0)
        XCTAssertEqual(old.revealedIndices, [])
        XCTAssertEqual(next.revealedIndices, [0])
        next.table = ChatTextTable(); next.index = 7
        view.streamingVisibleHeightChanged?()
        XCTAssertEqual(next.table?.notedRows, [7])
        let card = item(3, context: context)
        card.papercutLayout = true
        row.bind(card)
        XCTAssertNil(row.text)
        XCTAssertNil(view.superview)
    }

    func testReplacedLayoutsAndRemovedBlocksAreReleased() {
        let context = BlockContext(), row = ReusedChatTextRow(frame: .zero)
        weak var oldItem: ChatMessageItem?
        weak var oldLayout: TextViewLayout?
        weak var removedText: TextView?
        autoreleasepool {
            let old = item(1, count: 3, context: context)
            oldItem = old; oldLayout = old.textLayout.blocks[0].text
            row.bind(old)
            removedText = row.text?.textViews.last
            row.bind(item(2, context: context))
        }
        XCTAssertNil(oldItem)
        XCTAssertNil(oldLayout)
        XCTAssertNil(removedText)
    }

    func testReusedPixelsMatchReplacementAcrossBlockChanges() throws {
        var comparisons = 0
        for scale in [CGFloat(1), 2, 3] {
            System.updateScaleFactor(scale)
            for width in [CGFloat(160), 380] {
                let context = BlockContext(), row = ReusedChatTextRow(frame: .zero), baseline = ReplacementChatTextRow(frame: .zero)
                for (step, count) in [1, 3, 12, 12, 2, 0, 4].enumerated() {
                    let a = item(step, count: count, quoted: step % 2 == 0, context: context)
                    let b = item(step, count: count, quoted: step % 2 == 0, context: context)
                    a.textLayout.measure(width: width); b.textLayout.measure(width: width)
                    a.textOrigin = NSPoint(x: 9, y: CGFloat(step * 2)); b.textOrigin = a.textOrigin
                    row.bind(a); baseline.bind(b)
                    let actual = try XCTUnwrap(row.text), expected = try XCTUnwrap(baseline.text)
                    XCTAssertEqual(actual.frame, expected.frame)
                    let size = NSSize(width: width + 20, height: max(20, a.textLayout.size.height + 20))
                    actual.setFrameSize(size); expected.setFrameSize(size)
                    XCTAssertEqual(ViewSnapshot.render(actual, scale: scale).differingPixels(from: ViewSnapshot.render(expected, scale: scale), tolerance: 0), 0, "scale=\(scale), width=\(width), step=\(step)")
                    comparisons += 1
                }
            }
        }
        System.updateScaleFactor(2)
        XCTAssertEqual(comparisons, 42)
    }

    func testInlineMediaReuseReplacementAndSpoilerVisibility() throws {
        let context = BlockContext(), row = ReusedChatTextRow(frame: .zero)
        func mediaItem(_ id: Int, mediaId: Int64?, spoiler: Bool) -> ChatMessageItem {
            let text = NSMutableAttributedString(string: "🦆 Message \(id)", attributes: [.font: NSFont.systemFont(ofSize: 16), .foregroundColor: NSColor.black])
            if let mediaId {
                text.addAttribute(TextInputAttributes.embedded, value: InlineStickerItem(.attribute(Emoji(fileId: mediaId))), range: NSRange(location: 0, length: 2))
            }
            if spoiler { text.addAttribute(TextInputAttributes.spoiler, value: true, range: text.range) }
            let layout = FoldingTextLayout(attributedString: text, blocks: [TextViewLayout(text)], blockRanges: [text.range], context: context, revealed: [])
            layout.measure(width: 240)
            return ChatMessageItem(id: id, layout: layout)
        }
        row.bind(mediaItem(1, mediaId: 10, spoiler: false))
        let view = try XCTUnwrap(row.text), textView = try XCTUnwrap(view.textViews.first)
        let first = try XCTUnwrap(textView.embeddedContainer.sublayers?.first)
        row.bind(mediaItem(2, mediaId: 10, spoiler: true))
        XCTAssertTrue(row.text === view)
        XCTAssertTrue(textView.embeddedContainer.sublayers?.first === first)
        XCTAssertEqual(first.opacity, 0)
        XCTAssertFalse(textView.subviews.filter { $0 is InvisibleInkDustView }.isEmpty)
        row.bind(mediaItem(3, mediaId: 10, spoiler: false))
        XCTAssertEqual(first.opacity, 1)
        XCTAssertTrue(textView.subviews.filter { $0 is InvisibleInkDustView }.isEmpty)
        row.bind(mediaItem(4, mediaId: 11, spoiler: false))
        XCTAssertFalse(textView.embeddedContainer.sublayers?.first === first)
        XCTAssertNil(first.superlayer)
        row.bind(mediaItem(5, mediaId: nil, spoiler: false))
        XCTAssertTrue(textView.embeddedContainer.sublayers?.isEmpty ?? true)
    }


    func testOneShotEmojiAndAvatarsRestartWithoutRebuildingTextViews() throws {
        let context = BlockContext(), row = ReusedChatTextRow(frame: .zero)
        func next(_ id: Int, avatar: Bool, policy: PlayPolicy?) -> ChatMessageItem {
            let text = NSMutableAttributedString(string: "🦆 Message \(id)", attributes: [.font: NSFont.systemFont(ofSize: 16), .foregroundColor: NSColor.black])
            let media = InlineStickerItem(avatar ? .avatar(Peer(id: PeerId(value: 10))) : .attribute(Emoji(fileId: 10)))
            media.playPolicy = policy
            text.addAttribute(TextInputAttributes.embedded, value: media, range: NSRange(location: 0, length: 2))
            let layout = FoldingTextLayout(attributedString: text, blocks: [TextViewLayout(text)], blockRanges: [text.range], context: context, revealed: [])
            layout.measure(width: 240)
            return ChatMessageItem(id: id, layout: layout)
        }
        row.bind(next(0, avatar: false, policy: .loop))
        let view = try XCTUnwrap(row.text), text = try XCTUnwrap(view.textViews.first)
        var previous = try XCTUnwrap(text.embeddedContainer.sublayers?.first)
        for (index, value) in [(false, PlayPolicy.framesCount(1)), (false, .framesCount(1)), (false, .loop), (true, .loop), (true, .loop)].enumerated() {
            row.bind(next(index + 1, avatar: value.0, policy: value.1))
            let media = try XCTUnwrap(text.embeddedContainer.sublayers?.first)
            XCTAssertTrue(row.text === view)
            XCTAssertTrue(row.text?.textViews.first === text)
            XCTAssertFalse(media === previous)
            XCTAssertNil(previous.superlayer)
            previous = media
        }
    }


    func testFoldedExpandedQuotesMatchReplacementAndActiveMasksRejectReuse() throws {
        let context = BlockContext(), row = ReusedChatTextRow(frame: .zero), baseline = ReplacementChatTextRow(frame: .zero)
        for step in 0..<4 {
            let string = Array(repeating: "Quoted message \(step) مرحبا", count: 8).joined(separator: "\n")
            let a = item(step, quoted: true, context: context, text: string, collapsable: true)
            let b = item(step, quoted: true, context: context, text: string, collapsable: true)
            XCTAssertTrue(a.textLayout.blocks[0].canReveal)
            if step % 2 == 1 { a.textLayout.toggle(0); b.textLayout.toggle(0) }
            let previous = row.text
            row.bind(a); baseline.bind(b)
            if let previous { XCTAssertTrue(row.text === previous) }
            let actual = try XCTUnwrap(row.text), expected = try XCTUnwrap(baseline.text)
            XCTAssertEqual(actual.frame, expected.frame)
            XCTAssertEqual(ViewSnapshot.render(actual, scale: 2).differingPixels(from: ViewSnapshot.render(expected, scale: 2), tolerance: 0), 0)
        }
        let old = try XCTUnwrap(row.text)
        let layout = try XCTUnwrap((row.item as? ChatMessageItem)?.textLayout)
        layout.toggle(0)
        old.update(layout: layout, animated: true)
        let wrapper = try XCTUnwrap(old.subviews.first?.layer)
        let quoteMask = try XCTUnwrap(wrapper.mask ?? wrapper.sublayers?.compactMap { $0.mask }.first)
        let animation = CABasicAnimation(keyPath: "opacity")
        animation.fromValue = 0; animation.toValue = 1; animation.duration = 20
        quoteMask.add(animation, forKey: "test")
        wrapper.removeAllAnimations()
        old.layer?.removeAllAnimations()
        old.textViews.forEach { $0.layer?.removeAllAnimations() }
        XCTAssertFalse(old.updateForReusedContent(layout: item(5, context: context).textLayout))
        XCTAssertTrue(old.textViews.first?.textLayout === layout.blocks[0].text)
        row.bind(item(5, context: context))
        XCTAssertFalse(row.text === old)
    }

}
