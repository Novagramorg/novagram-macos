import Cocoa
import XCTest
import TGUIKit
@testable import FoldingViewHarness
@testable import ChatLayerEngine

final class TextQuoteScanTests: XCTestCase {
    override func setUp() { TGUIKitTestBootstrap.install() }

    func check(_ layout: TextViewLayout, file: StaticString = #filePath, line: UInt = #line) {
        let last = layout.attributedString.containsAttribute(attributeName: TextInputAttributes.quote) as? TextViewBlockQuoteData
        XCTAssertEqual(layout.hasBlockQuotes, last != nil, file: file, line: line)
        XCTAssertEqual(layout.blockCollapsable, last?.collapsable ?? false, file: file, line: line)
        let expected: Bool
        if let range = layout.lines.last?.range {
            expected = layout.attributedString.attributedSubstring(from: range).containsAttribute(attributeName: TextInputAttributes.quote) is TextViewBlockQuoteData
        } else { expected = false }
        XCTAssertEqual(layout.lastLineIsQuote, expected, file: file, line: line)
    }

    func testLastQuoteSemanticsAcrossFragmentationRangesAndMalformedValues() {
        let quotes: [Any] = [TextViewBlockQuoteData(id: 1, colors: .init(main: .blue)), TextViewBlockQuoteData(id: 2, colors: .init(main: .red), collapsable: true), NSNull(), NSNumber(value: false), "invalid"]
        for seed in 0..<1024 {
            let string = NSMutableAttributedString(string: seed % 7 == 0 ? "" : "first block\nsecond block\nlast block", attributes: [.font: NSFont.systemFont(ofSize: 14)])
            for index in 0..<string.length {
                string.addAttribute(.foregroundColor, value: index % 2 == 0 ? NSColor.black : .blue, range: NSRange(location: index, length: 1))
                if seed & (1 << (index % 10)) != 0 { string.addAttribute(TextInputAttributes.quote, value: quotes[(seed + index / 3) % quotes.count], range: NSRange(location: index, length: 1)) }
            }
            let value: NSAttributedString = seed % 2 == 0 ? string : NSAttributedString(attributedString: string)
            let layout = TextViewLayout(value)
            layout.measure(width: seed % 2 == 0 ? 80 : 400)
            check(layout)
        }
    }

    func testMutationAndTextStorageDoNotReturnCachedQuoteState() {
        for text: NSMutableAttributedString in [NSMutableAttributedString(string: "same text\nlast line"), NSTextStorage(string: "same text\nlast line")] {
            text.addAttribute(.font, value: NSFont.systemFont(ofSize: 14), range: text.range)
            let layout = TextViewLayout(text)
            layout.measure(width: 200)
            for pass in 0..<128 {
                text.removeAttribute(TextInputAttributes.quote, range: text.range)
                check(layout)
                let start = pass % text.length
                text.addAttribute(TextInputAttributes.quote, value: TextViewBlockQuoteData(id: pass, colors: .init(main: .blue), collapsable: pass % 2 == 0), range: NSRange(location: start, length: 1))
                check(layout)
                if start < text.length - 1 {
                    text.addAttribute(TextInputAttributes.quote, value: NSNull(), range: NSRange(location: text.length - 1, length: 1))
                    check(layout)
                }
            }
        }
    }

    func testLastLineBoundariesAndUnicodeMatchSubstringLookup() {
        let strings = ["", "\n", "first\nlast\n", "quote\nplain", "مرحبا بالعالم\nآخر سطر", "👩🏽‍💻 café 中文\n👨‍👩‍👧‍👦 end", "a\u{2028}b\u{2029}c"]
        for string in strings {
            for width: CGFloat in [40, 100, 500] {
                let text = NSMutableAttributedString(string: string, attributes: [.font: NSFont.systemFont(ofSize: 14)])
                let layout = TextViewLayout(text)
                layout.measure(width: width)
                check(layout)
                for index in 0..<text.length {
                    text.removeAttribute(TextInputAttributes.quote, range: text.range)
                    text.addAttribute(TextInputAttributes.quote, value: TextViewBlockQuoteData(id: index, colors: .init(main: .blue)), range: NSRange(location: index, length: 1))
                    check(layout)
                }
            }
        }
    }

    func testEqualQuoteValuesAndMalformedTrailingValuesPreserveFlags() {
        let text = NSMutableAttributedString(string: "first second third", attributes: [.font: NSFont.systemFont(ofSize: 14)])
        for index in 0..<text.length {
            text.addAttribute(.foregroundColor, value: index % 2 == 0 ? NSColor.black : .blue, range: NSRange(location: index, length: 1))
            text.addAttribute(TextInputAttributes.quote, value: TextViewBlockQuoteData(id: 1, colors: .init(main: .blue), collapsable: true), range: NSRange(location: index, length: 1))
        }
        let layout = TextViewLayout(text)
        layout.measure(width: 90)
        check(layout)
        XCTAssertTrue(layout.hasBlockQuotes)
        text.addAttribute(TextInputAttributes.quote, value: NSNull(), range: NSRange(location: text.length - 2, length: 1))
        check(layout)
        text.removeAttribute(TextInputAttributes.quote, range: NSRange(location: text.length - 1, length: 1))
        check(layout)
        XCTAssertFalse(layout.hasBlockQuotes)
    }

    func assertEqual(_ current: ChatLayerMessageTextPresentation?, _ reference: ChatLayerMessageTextPresentation?, file: StaticString = #filePath, line: UInt = #line) {
        guard let current, let reference else {
            XCTAssertEqual(current == nil, reference == nil, file: file, line: line)
            return
        }
        XCTAssertEqual(current.size, reference.size, file: file, line: line)
        XCTAssertEqual(current.nativeFeatures, reference.nativeFeatures, file: file, line: line)
        XCTAssertEqual(current.requiresRevealAction, reference.requiresRevealAction, file: file, line: line)
        XCTAssertEqual(current.blocks.map(\.frame), reference.blocks.map(\.frame), file: file, line: line)
        XCTAssertEqual(current.blocks.map(\.hasLinks), reference.blocks.map(\.hasLinks), file: file, line: line)
        XCTAssertEqual(current.blocks.map(\.clipsTextToBounds), reference.blocks.map(\.clipsTextToBounds), file: file, line: line)
        XCTAssertEqual(current.blocks.map { $0.folding != nil }, reference.blocks.map { $0.folding != nil }, file: file, line: line)
        XCTAssertEqual(current.blocks.map { ObjectIdentifier($0.layout) }, reference.blocks.map { ObjectIdentifier($0.layout) }, file: file, line: line)
    }

    func testCombinedPreparationScanMatchesCapturedProductionForMixedRuns() {
        let context = BlockContext(), factory = ChatTextReuseTests()
        let keys: [NSAttributedString.Key] = [TextInputAttributes.quote, TextInputAttributes.spoiler, TextInputAttributes.customEmoji, TextInputAttributes.formattedDate, .link]
        let quotes: [Any] = [TextViewBlockQuoteData(id: 1, colors: .init(main: .blue)), NSNull(), TextViewBlockQuoteData(id: 2, colors: .init(main: .red), collapsable: true)]
        for sample in 0..<1024 {
            let item = factory.item(sample, count: 1 + sample % 3, quoted: sample % 2 == 0, context: context, streaming: sample % 13 == 0, text: "first\nsecond\nthird\nfourth\nfifth", collapsable: sample % 7 == 0)
            for (index, block) in item.textLayout.blocks.enumerated() {
                let text = block.text.attributedString as! NSMutableAttributedString
                for (keyIndex, key) in keys.enumerated() where sample & (1 << keyIndex) != 0 {
                    let start = (sample + index + keyIndex) % text.length
                    text.addAttribute(key, value: key == TextInputAttributes.quote ? quotes[(sample + index) % 3] : NSNumber(value: false), range: NSRange(location: start, length: 1))
                }
                if sample % 3 == 0 { text.addAttribute(TextInputAttributes.quote, value: quotes[(sample / 3) % 3], range: NSRange(location: text.length - 1, length: 1)) }
            }
            let current = ChatLayerMessageTextPresentation.simpleText(item.textLayout)
            let reference = ChatLayerMessageTextPresentation.referenceSimpleText(item.textLayout)
            if let current, reference == nil {
                XCTAssertTrue(current.requiresRevealAction)
                XCTAssertTrue(item.textLayout.blocks.contains { $0.canReveal })
                XCTAssertEqual(current.nativeFeatures, [])
                XCTAssertEqual(current.size, item.textLayout.size)
                var y: CGFloat = 0
                for (prepared, block) in zip(current.blocks, item.textLayout.blocks) {
                    let height = block.isRevealed ? block.layoutSize.height : block.size.height
                    XCTAssertEqual(prepared.frame, NSRect(x: 0, y: y, width: block.layoutSize.width, height: height))
                    XCTAssertTrue(prepared.layout === block.text)
                    XCTAssertEqual(prepared.folding != nil, block.canReveal)
                    if let folding = prepared.folding {
                        XCTAssertTrue(folding.layout.text === block.text)
                        XCTAssertEqual(folding.layout.size, block.size)
                        XCTAssertEqual(folding.layout.isRevealed, block.isRevealed)
                        XCTAssertEqual(folding.layout.collapsable, block.collapsable)
                        XCTAssertTrue(folding.layout.mask === block.mask)
                        XCTAssertTrue(folding.layout.arrowDown === block.arrowDown)
                        XCTAssertTrue(folding.layout.arrowUp === block.arrowUp)
                    }
                    y += height
                }
            } else {
                assertEqual(current, reference)
            }
        }
    }
    func testTextReplacementWithStaleLineRangesReturnsNoLastLineQuote() {
        for mutable in [false, true] {
            let value = NSMutableAttributedString(string: "first line\nsecond line\nlast line", attributes: [.font: NSFont.systemFont(ofSize: 14)])
            let layout = TextViewLayout(value)
            layout.measure(width: 100)
            XCTAssertFalse(layout.lines.isEmpty)
            for replacement in ["x", ""] {
                if mutable { value.replaceCharacters(in: value.range, with: replacement) }
                else { layout.setAttributedString(NSAttributedString(string: replacement)) }
                XCTAssertFalse(layout.lastLineIsQuote)
                XCTAssertFalse(layout.hasBlockQuotes)
                XCTAssertFalse(layout.blockCollapsable)
            }
        }
    }

}
