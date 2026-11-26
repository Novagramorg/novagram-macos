import Cocoa
import XCTest
import TGUIKit
@testable import FoldingViewHarness

final class CaptionReuseTests: XCTestCase {
    override func setUp() { TGUIKitTestBootstrap.install() }

    func caption(_ id: Int, stableId: UInt32? = nil, text: String? = nil, context: BlockContext, blocks: Int = 1, quoted: Bool = false, streaming: Bool = false, loading: Bool = false, offset: NSPoint = .zero) -> ChatRowItem.RowCaption {
        let body = ChatTextReuseTests().item(id, count: blocks, quoted: quoted, context: context, streaming: streaming, text: text, collapsable: quoted)
        return .init(messageId: id, id: stableId ?? UInt32(id), layout: body.textLayout, loading: loading, offset: offset)
    }

    func testEditedAndRecycledCaptionsRetainIdleViewsAndMoveToCurrentFrames() throws {
        for quoted in [false, true] {
            let context = BlockContext(), row = ReusedCaptionRow(frame: .zero)
            row.bind(ChatRowItem([caption(1, context: context, blocks: 3, quoted: quoted)]))
            let view = try XCTUnwrap(row.views.first), blocks = view.textViews
            for id in [1, 2, 3] {
                let next = caption(id, text: "Edited caption \(id)\n", context: context, blocks: 3, quoted: quoted, offset: NSPoint(x: 12, y: 47))
                row.bind(ChatRowItem([next]))
                XCTAssertTrue(row.views.first === view)
                XCTAssertTrue(zip(view.textViews, blocks).allSatisfy { $0 === $1 })
                XCTAssertEqual(row.ids, [UInt32(id)])
                XCTAssertEqual(view.frame, row.captionFrame(row.item as! ChatRowItem, caption: next))
                XCTAssertEqual(row.rowView.subviews.count, 2)
                XCTAssertEqual(view.string, next.layout.string)
            }
        }
    }

    func testUnchangedCaptionsAreReservedBeforeRecyclingOthers() throws {
        let context = BlockContext(), row = ReusedCaptionRow(frame: .zero)
        let first = caption(1, context: context), second = caption(2, context: context), third = caption(3, context: context)
        row.bind(ChatRowItem([first, second, third]))
        let originals = row.views
        second.layout.blocks[0].text.selectedRange.range = NSRange(location: 0, length: 3)
        let updated = caption(2, context: context)
        let next = ChatRowItem([caption(4, context: context), updated, first])
        row.bind(next)
        XCTAssertTrue(row.views[0] === originals[2])
        XCTAssertTrue(row.views[1] === originals[1])
        XCTAssertTrue(row.views[2] === originals[0])
        XCTAssertEqual(row.ids, [4, 2, 1])
        XCTAssertEqual(updated.layout.blocks[0].text.selectedRange.range, NSRange(location: 0, length: 3))
        for (index, view) in row.views.enumerated() { view.revealBlockAtIndex?(index) }
        XCTAssertEqual(next.revealed.map { $0.1 }, [4, 2, 1])
    }

    func testSameStableIdDifferentMessageResetsSelectionAndUsesCurrentCallback() throws {
        let context = BlockContext(), row = ReusedCaptionRow(frame: .zero)
        let old = caption(1, stableId: 7, text: "Same caption", context: context)
        row.bind(ChatRowItem([old]))
        old.layout.blocks[0].text.selectedRange.range = NSRange(location: 0, length: 4)
        let view = try XCTUnwrap(row.views.first)
        let next = caption(2, stableId: 7, text: "Same caption", context: context)
        let item = ChatRowItem([next])
        row.bind(item)
        XCTAssertTrue(row.views.first === view)
        XCTAssertEqual(next.layout.blocks[0].text.selectedRange.range.location, NSNotFound)
        XCTAssertEqual(old.layout.blocks[0].text.selectedRange.range, NSRange(location: 0, length: 4))
        view.revealBlockAtIndex?(3)
        XCTAssertEqual(item.revealed.map { $0.1 }, [2])
        let baseline = ReplacementCaptionRow(frame: .zero)
        baseline.bind(ChatRowItem([caption(1, stableId: 7, text: "Same caption", context: context)]))
        let legacyNext = ChatRowItem([caption(2, stableId: 7, text: "Same caption", context: context)])
        baseline.bind(legacyNext)
        baseline.views[0].revealBlockAtIndex?(3)
        XCTAssertEqual(legacyNext.revealed.map { $0.1 }, [1])
    }

    func testSameCaptionPreservesSelectionAndUpdatesLoadingIdentity() throws {
        let context = BlockContext(), row = ReusedCaptionRow(frame: .zero)
        let first = caption(1, context: context)
        row.bind(ChatRowItem([first]))
        let view = try XCTUnwrap(row.views.first)
        first.layout.blocks[0].text.selectedRange.range = NSRange(location: 1, length: 3)
        for loading in [true, false, true] {
            let next = caption(1, context: context, loading: loading)
            let item = ChatRowItem([next])
            row.bind(item)
            XCTAssertTrue(row.views.first === view)
            XCTAssertEqual(next.layout.blocks[0].text.selectedRange.range, NSRange(location: 1, length: 3))
            XCTAssertEqual(row.shimmers, [loading])
            view.revealBlockAtIndex?(0)
            XCTAssertEqual(item.revealed.map { $0.1 }, [1])
        }
    }

    func testAccountChangeDoesNotReuseEvenWithSameIdentityAndText() throws {
        let row = ReusedCaptionRow(frame: .zero)
        row.bind(ChatRowItem([caption(1, context: BlockContext())]))
        let view = try XCTUnwrap(row.views.first)
        row.bind(ChatRowItem([caption(1, context: BlockContext())]))
        XCTAssertFalse(row.views.first === view)
        XCTAssertNil(view.superview)
    }

    func testActiveInteractionsAnimationsAndStreamingKeepReplacementPath() throws {
        for reason in 0..<6 {
            let context = BlockContext(), row = ReusedCaptionRow(frame: .zero)
            row.bind(ChatRowItem([caption(1, context: context, streaming: reason == 4)]))
            let view = try XCTUnwrap(row.views.first), text = try XCTUnwrap(view.textViews.first)
            if reason == 0 { text.controlState = .Highlight }
            if reason == 1 { text.canBeResponder = false }
            if reason == 2 {
                let animation = CABasicAnimation(keyPath: "opacity")
                animation.fromValue = 0; animation.toValue = 1; animation.duration = 20
                view.layer?.add(animation, forKey: "test")
            }
            row.bind(ChatRowItem([caption(2, context: context, streaming: reason == 5)]), animated: reason == 3)
            XCTAssertFalse(row.views.first === view, "reason=\(reason)")
            if reason != 3 { XCTAssertNil(view.superview) }
        }
    }

    func testRemovedCaptionsAndItemsAreReleasedAndCallbacksDoNotRetainRows() {
        weak var removed: FoldingTextView?
        weak var oldItem: ChatRowItem?
        weak var rowReference: ReusedCaptionRow?
        let context = BlockContext()
        autoreleasepool {
            let row = ReusedCaptionRow(frame: .zero)
            rowReference = row
            autoreleasepool {
                let item = ChatRowItem([caption(1, context: context), caption(2, context: context)])
                oldItem = item
                row.bind(item)
                removed = row.views[1]
                row.bind(ChatRowItem([caption(1, context: context)]))
            }
            XCTAssertNil(oldItem)
            XCTAssertNil(removed)
            row.bind(ChatRowItem([]))
            XCTAssertTrue(row.views.isEmpty)
            XCTAssertEqual(row.rowView.subviews.count, 1)
        }
        XCTAssertNil(rowReference)
    }

    func testIneligibleCaptionDoesNotStealReservedSiblingOrWrongAccountView() throws {
        let a = BlockContext(), b = BlockContext(), row = ReusedCaptionRow(frame: .zero)
        row.bind(ChatRowItem([caption(1, context: a), caption(2, context: b)]))
        let old = row.views
        row.bind(ChatRowItem([caption(3, context: b)]))
        XCTAssertTrue(row.views[0] === old[1])
        XCTAssertNil(old[0].superview)
        row.bind(ChatRowItem([caption(4, context: b), caption(5, context: b)]))
        let active = row.views[0], reserved = row.views[1]
        active.textViews[0].controlState = .Highlight
        row.bind(ChatRowItem([caption(6, context: b), caption(5, context: b)]))
        XCTAssertTrue(row.views[1] === reserved)
        XCTAssertFalse(row.views[0] === active)
        XCTAssertFalse(row.views[0] === reserved)
    }

    func testInlineMediaAndSpoilerStateFollowRecycledCaption() throws {
        let context = BlockContext(), row = ReusedCaptionRow(frame: .zero)
        func media(_ id: Int, file: Int64?, spoiler: Bool = false, oneShot: Bool = false) -> ChatRowItem {
            let text = NSMutableAttributedString(string: "🦆 Caption \(id)", attributes: [.font: NSFont.systemFont(ofSize: 16), .foregroundColor: NSColor.black])
            if let file {
                let media = InlineStickerItem(.attribute(Emoji(fileId: file)))
                if oneShot { media.playPolicy = .framesCount(1) }
                text.addAttribute(TextInputAttributes.embedded, value: media, range: NSRange(location: 0, length: 2))
            }
            if spoiler { text.addAttribute(TextInputAttributes.spoiler, value: true, range: text.range) }
            let layout = FoldingTextLayout(attributedString: text, blocks: [TextViewLayout(text)], blockRanges: [text.range], context: context, revealed: [])
            layout.measure(width: 240)
            return ChatRowItem([.init(messageId: id, id: UInt32(id), layout: layout)])
        }
        row.bind(media(1, file: 10))
        let view = row.views[0], text = view.textViews[0]
        let looping = try XCTUnwrap(text.embeddedContainer.sublayers?.first)
        row.bind(media(2, file: 10, spoiler: true))
        XCTAssertTrue(row.views[0] === view)
        XCTAssertTrue(text.embeddedContainer.sublayers?.first === looping)
        XCTAssertEqual(looping.opacity, 0)
        row.bind(media(3, file: 10))
        XCTAssertEqual(looping.opacity, 1)
        row.bind(media(4, file: 11, oneShot: true))
        XCTAssertNil(looping.superlayer)
        let shot = try XCTUnwrap(text.embeddedContainer.sublayers?.first)
        row.bind(media(5, file: 11, oneShot: true))
        XCTAssertFalse(text.embeddedContainer.sublayers?.first === shot)
        XCTAssertNil(shot.superlayer)
        row.bind(media(6, file: nil))
        XCTAssertTrue(row.views[0] === view)
        XCTAssertTrue(text.embeddedContainer.sublayers?.isEmpty ?? true)
    }

    func testFoldedAndExpandedRecycledCaptionsMatchReplacement() throws {
        let context = BlockContext()
        let baseline = ReplacementCaptionRow(frame: CGRect(x: 0, y: 0, width: 320, height: 400))
        let candidate = ReusedCaptionRow(frame: baseline.frame)
        var first: FoldingTextView?
        for step in 0..<4 {
            for row in [baseline as CaptionRowEnvironment, candidate] {
                let text = Array(repeating: "Quote \(step) مرحبا", count: 8).joined(separator: "\n")
                let value = caption(step + 1, text: text, context: context, quoted: true)
                XCTAssertTrue(value.layout.blocks[0].canReveal)
                if step % 2 == 1 { value.layout.toggle(0) }
                row.bind(ChatRowItem([value]))
                row.finishLayout()
            }
            if let first { XCTAssertTrue(candidate.views[0] === first) }
            else { first = candidate.views[0] }
            let expected = ViewSnapshot.render(baseline), actual = ViewSnapshot.render(candidate)
            XCTAssertEqual(actual.differingPixels(from: expected, tolerance: 0), 0)
            XCTAssertGreaterThan(actual.pixels(darkerThan: 200), 100)
        }
    }

    func testChangedCaptionsPixelsMatchReplacementAcrossScalesAndReordering() throws {
        for scale in [CGFloat(1), 2, 3] {
            for quoted in [false, true] {
                let context = BlockContext()
                let baseline = ReplacementCaptionRow(frame: CGRect(x: 0, y: 0, width: 320, height: 600))
                let candidate = ReusedCaptionRow(frame: baseline.frame)
                for step in 0..<4 {
                    for row in [baseline as CaptionRowEnvironment, candidate] {
                        let values = step == 3 ? [] : (0..<(step == 2 ? 1 : 3)).map { i in
                            caption(step * 10 + i + 1, text: "Caption \(step) مرحبا 👩🏽‍💻 中文\nText \(i)", context: context, blocks: 2, quoted: quoted, offset: NSPoint(x: 7 + step, y: 130 * i + 5))
                        }
                        row.bind(ChatRowItem(step == 1 ? values.reversed() : values))
                        row.finishLayout()
                    }
                    let expected = ViewSnapshot.render(baseline, scale: scale)
                    let actual = ViewSnapshot.render(candidate, scale: scale)
                    if let directory = ProcessInfo.processInfo.environment["CAPTION_CAPTURE_DIRECTORY"] {
                        let root = URL(fileURLWithPath: directory)
                        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
                        let name = "\(Int(scale))_\(quoted)_\(step)"
                        try actual.write(to: root.appendingPathComponent(name + "_after.png"))
                        try expected.write(to: root.appendingPathComponent(name + "_before.png"))
                    }
                    if step != 3 { XCTAssertGreaterThan(actual.pixels(darkerThan: 200), 100) }
                    XCTAssertEqual(actual.differingPixels(from: expected, tolerance: 0), 0, "scale=\(scale), quoted=\(quoted), step=\(step)")
                }
            }
        }
    }
}
