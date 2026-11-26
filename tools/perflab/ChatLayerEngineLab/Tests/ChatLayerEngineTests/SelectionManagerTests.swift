import Cocoa
import XCTest
import TGUIKit
@testable import ChatLayerEngine

final class SelectionManagerTests: XCTestCase {
    override func setUp() { TGUIKitTestBootstrap.install() }

    final class Source: NSObject, ChatBubbleCustomTextSelection {
        var cleared = 0
        var onClear: (() -> Void)?
        func clearBubbleSelection() { cleared += 1; onClear?() }
        func applyBubbleSelection(begin: NSPoint, end: NSPoint, isStartRow: Bool, isEndRow: Bool, reversed: Bool) -> [ChatBubbleSelectionFragment] { [] }
    }

    func testMixedRenderersKeepMessageAndFragmentOrder() {
        let source = Source()
        var comparisons = 0
        for mask in 0..<256 {
            for headers in [false, true] {
                let reference = LegacySelectManager(), current = SelectManager()
                for row in 0..<4 {
                    for block in 0..<2 {
                        let text = NSAttributedString(string: "row \(row) paragraph \(block) 🦆 café שלום\n", attributes: [.foregroundColor: row % 2 == 0 ? NSColor.red : NSColor.blue, .link: "target-\(row)"])
                        let range = NSRange(location: block, length: text.length - block - row)
                        let header = headers && block == 0 ? "Author \(row)" : nil
                        reference.add(range: range, textView: nil, layout: nil, text: text, header: header, stableId: row, index: block)
                        if mask & (1 << (row * 2 + block)) == 0 {
                            current.add(range: range, textView: nil, layout: nil, text: text, header: header, stableId: row, index: block)
                        } else {
                            current.addBubble(fragment: .init(attributedString: text, range: range, index: block), source: source, header: header, stableId: row)
                        }
                    }
                }
                XCTAssertTrue(current.selectedText.isEqual(to: reference.selectedText), "mask=\(mask), headers=\(headers)")
                comparisons += 1
            }
        }
        XCTAssertEqual(comparisons, 512)
        let broken = LegacySelectManager(), fixed = SelectManager()
        for (index, string) in ["A", "B", "C"].enumerated() {
            let text = NSAttributedString(string: string)
            let range = NSRange(location: 0, length: 1)
            if index == 1 {
                broken.addBubble(fragment: .init(attributedString: text, range: range, index: 0), source: source, header: nil, stableId: index)
                fixed.addBubble(fragment: .init(attributedString: text, range: range, index: 0), source: source, header: nil, stableId: index)
            } else {
                broken.add(range: range, textView: nil, layout: nil, text: text, header: nil, stableId: index, index: 0)
                fixed.add(range: range, textView: nil, layout: nil, text: text, header: nil, stableId: index, index: 0)
            }
        }
        XCTAssertEqual(broken.selectedText.string, "B\n\n\nC\n\n\nA")
        XCTAssertEqual(fixed.selectedText.string, "C\n\n\nB\n\n\nA")
    }

    func testCustomFragmentsReplaceByIndexAndSortInReadingOrder() {
        let manager = SelectManager(), source = Source()
        for (index, text) in [(2, "third"), (0, "first"), (1, "old"), (1, "second")] {
            manager.addBubble(fragment: .init(attributedString: NSAttributedString(string: text), range: NSRange(location: 0, length: text.count), index: index), source: source, header: nil, stableId: "message")
        }
        XCTAssertEqual(manager.selectedText.string, "first\nsecond\nthird")
        manager.removeAll()
        XCTAssertEqual(source.cleared, 1)
        XCTAssertTrue(manager.isEmpty)
        XCTAssertEqual(manager.selectedText.length, 0)
    }

    func testOffscreenSnapshotsPreserveTextAndDoNotRetainOrClearReusedViews() {
        let manager = SelectManager()
        var source: ChatRichTextRowView? = ChatRichTextRowView()
        weak var weakSource = source
        let value = NSAttributedString(string: "formatted 🦆", attributes: [.link: "target", .foregroundColor: NSColor.red])
        manager.addBubble(fragment: .init(attributedString: value, range: NSRange(location: 0, length: value.length), index: 0), source: source!, header: "Author", stableId: "offscreen")
        let restore = preserveBubbleSelection(manager, stableId: "offscreen")
        manager.removeAll()
        XCTAssertEqual(source?.clearCount, 1)
        restore()
        XCTAssertTrue(manager.selectedText.isEqual(to: value))
        XCTAssertEqual(bubbleSelectionSummary(manager, stableId: "offscreen").count, 1)
        XCTAssertFalse(bubbleSelectionSummary(manager, stableId: "offscreen")[0].hasSource)
        XCTAssertTrue(bubbleSelectionSummary(manager, stableId: "offscreen")[0].rich)
        restore()
        XCTAssertEqual(bubbleSelectionSummary(manager, stableId: "offscreen").count, 1)
        manager.removeAll()
        XCTAssertEqual(source?.clearCount, 1)
        source = nil
        XCTAssertNil(weakSource)
        restore()
        XCTAssertTrue(manager.selectedText.isEqual(to: value))
        manager.removeAll()
        XCTAssertTrue(manager.isEmpty)
    }

    func testOffscreenMixedSelectionMatchesVisibleSelectionAndCanShrink() {
        let manager = SelectManager(), source = Source()
        let text = NSAttributedString(string: "middle")
        manager.addBubble(fragment: .init(attributedString: text, range: NSRange(location: 1, length: 4), index: 0), source: source, header: nil, stableId: 1)
        let restore = preserveBubbleSelection(manager, stableId: 1)
        manager.removeAll()
        for _ in 0..<4 {
            let a = NSAttributedString(string: "last"), c = NSAttributedString(string: "first")
            manager.add(range: NSRange(location: 0, length: 4), textView: nil, layout: nil, text: a, header: nil, stableId: 0, index: 0)
            restore()
            manager.add(range: NSRange(location: 0, length: 5), textView: nil, layout: nil, text: c, header: nil, stableId: 2, index: 0)
            XCTAssertEqual(manager.selectedText.string, "first\n\n\n...iddl...\n\n\nlast")
            manager.removeAll()
        }
        manager.addBubble(fragment: .init(attributedString: text, range: NSRange(location: 2, length: 1), index: 0), source: source, header: nil, stableId: 1)
        XCTAssertEqual(manager.selectedText.string, "d")
    }

    func testNativeWhitespaceAttributesAndEmptyRangesPreserveLegacyFormatting() {
        for strings in [["", " ", "\n"], [" a\u{2028}b ", "c\u{fffc}d", "hello\r\n"], ["😀", "مرحبا", "é"]] {
            let original = LegacySelectManager(), current = SelectManager()
            for (index, string) in strings.enumerated() {
                let value = NSAttributedString(string: string, attributes: [.font: NSFont.boldSystemFont(ofSize: 15)])
                let range = index == 1 ? NSRange(location: NSNotFound, length: 0) : NSRange(location: 0, length: value.length)
                original.add(range: range, textView: nil, layout: nil, text: value, header: "Author", stableId: index, index: 0)
                current.add(range: range, textView: nil, layout: nil, text: value, header: "Author", stableId: index, index: 0)
            }
            XCTAssertTrue(current.selectedText.isEqual(to: original.selectedText))
        }
    }

    func testClearingDistinctSourcesRemainsOrderedAndDeduplicated() {
        let manager = SelectManager()
        var cleared: [Int] = []
        let sources = (0..<512).map { index -> Source in
            let source = Source()
            source.onClear = { cleared.append(index) }
            return source
        }
        for (index, source) in sources.enumerated() {
            for block in 0..<2 {
                let text = NSAttributedString(string: "text")
                manager.addBubble(fragment: .init(attributedString: text, range: NSRange(location: 0, length: 4), index: block), source: source, header: nil, stableId: index)
            }
        }
        manager.removeAll()
        XCTAssertEqual(cleared, Array(0..<512))
        XCTAssertTrue(sources.allSatisfy { $0.cleared == 1 })
    }

    func testCarriageReturnHeaderPreservesLegacyNewlineFormatting() {
        let original = LegacySelectManager(), current = SelectManager()
        let text = NSAttributedString(string: "")
        for index in 0..<2 {
            let range = NSRange(location: NSNotFound, length: 0)
            original.add(range: range, textView: nil, layout: nil, text: text, header: "Header\r", stableId: index, index: 0)
            current.add(range: range, textView: nil, layout: nil, text: text, header: "Header\r", stableId: index, index: 0)
        }
        XCTAssertTrue(current.selectedText.isEqual(to: original.selectedText))
    }

    func testInvalidOrMutatedRangesCannotCrashCopyAndResetClearsOrder() {
        let manager = SelectManager(), source = Source()
        let value = NSMutableAttributedString(string: "before")
        manager.addBubble(fragment: .init(attributedString: value, range: NSRange(location: 0, length: 6), index: 0), source: source, header: nil, stableId: 1)
        value.mutableString.setString("a")
        XCTAssertEqual(manager.selectedText.length, 0)
        manager.removeAll()
        for range in [NSRange(location: Int.max, length: Int.max), NSRange(location: 0, length: Int.max), NSRange(location: 2, length: 0)] {
            manager.addBubble(fragment: .init(attributedString: value, range: range, index: 0), source: source, header: nil, stableId: 1)
            XCTAssertEqual(manager.selectedText.length, 0)
        }
        manager.removeAll()
        source.onClear = {
            manager.addBubble(fragment: .init(attributedString: value, range: NSRange(location: 0, length: 1), index: 0), source: source, header: "no header for a single message", stableId: 2)
        }
        manager.addBubble(fragment: .init(attributedString: value, range: NSRange(location: 0, length: 1), index: 0), source: source, header: nil, stableId: 1)
        manager.removeAll()
        XCTAssertEqual(manager.selectedText.string, "a")
        source.onClear = nil
        manager.removeAll()
        XCTAssertTrue(manager.isEmpty)
    }
}
