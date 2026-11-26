import Cocoa
import XCTest
import TGUIKit
import InputTextView
@testable import ChatLayerEngine

final class MessageTextPreparationTests: XCTestCase {
    override func setUp() { TGUIKitTestBootstrap.install() }

    func assertEquivalent(_ layout: FoldingTextLayout, file: StaticString = #filePath, line: UInt = #line) {
        let original = LegacyChatLayerMessageTextPresentation(layout)
        let current = ChatLayerMessageTextPresentation(layout)
        XCTAssertEqual(Set(original.nativeFeatures.filter { $0 != .quote }.map { String(describing: $0) }), Set(current.nativeFeatures.filter { $0 != .quote }.map { String(describing: $0) }), file: file, line: line)
        XCTAssertEqual(original.size, current.size, file: file, line: line)
        XCTAssertEqual(original.blocks.map(\.frame), current.blocks.map(\.frame), file: file, line: line)
        XCTAssertEqual(original.blocks.map(\.hasLinks), current.blocks.map(\.hasLinks), file: file, line: line)
        XCTAssertEqual(layout.blocks.map { $0.text.hasBlockQuotes }, current.blocks.map(\.clipsTextToBounds), file: file, line: line)
        XCTAssertEqual(original.blocks.map { ObjectIdentifier($0.layout) }, current.blocks.map { ObjectIdentifier($0.layout) }, file: file, line: line)
    }

    func testCoreFoundationScanMatchesOriginalNonQuoteFeaturesForOverlappingAttributeRuns() {
        let keys = [TextInputAttributes.quote, TextInputAttributes.spoiler, TextInputAttributes.customEmoji, TextInputAttributes.formattedDate, .link, NSAttributedString.Key("unrelated")]
        let quote = TextViewBlockQuoteData(id: 1, colors: .init(main: .blue))
        let strings = ["", "a", "Latin العربية 👩🏽‍💻 中文\nend", "A longer message with overlapping attribute runs and different values."]
        var comparisons = 0
        for sample in 0..<512 {
            for immutable in [false, true] {
                let value = NSMutableAttributedString(string: strings[sample % strings.count], attributes: [.font: NSFont.systemFont(ofSize: 14)])
                for (index, key) in keys.enumerated() where sample & (1 << index) != 0 && value.length > 0 {
                    let start = (sample + index * 7) % value.length
                    let length = max(1, (value.length - start) / 2)
                    let attribute: Any
                    if key == TextInputAttributes.quote { attribute = sample & 64 != 0 ? quote : NSNull() }
                    else { attribute = sample & 128 != 0 ? NSNumber(value: false) : "value" }
                    value.addAttribute(key, value: attribute, range: NSRange(location: start, length: length))
                    if start > 0 { value.addAttribute(key, value: attribute, range: NSRange(location: 0, length: 1)) }
                }
                let text = TextViewLayout(immutable ? NSAttributedString(attributedString: value) : value)
                let source = FoldingTextLayout(blocks: [.init(text: text, isRevealed: sample & 256 == 0, size: NSSize(width: 150, height: 20))], appendingAnimation: sample % 7 == 0)
                assertEquivalent(source)
                comparisons += 1
            }
        }
        XCTAssertEqual(comparisons, 1024)
    }

    func testMutableAttributesAreRescannedWithoutStaleFeatureOrLinkState() {
        let value = NSMutableAttributedString(string: "changing", attributes: [.font: NSFont.systemFont(ofSize: 14)])
        let text = TextViewLayout(value)
        let source = FoldingTextLayout(blocks: [.init(text: text)])
        XCTAssertTrue(ChatLayerMessageTextPresentation(source).nativeFeatures.isEmpty)
        XCTAssertFalse(ChatLayerMessageTextPresentation(source).blocks[0].hasLinks)
        value.addAttribute(TextInputAttributes.spoiler, value: false, range: NSRange(location: 1, length: 3))
        value.addAttribute(.link, value: "target", range: NSRange(location: 5, length: 2))
        assertEquivalent(source)
        XCTAssertEqual(ChatLayerMessageTextPresentation(source).nativeFeatures, [.spoiler])
        XCTAssertTrue(ChatLayerMessageTextPresentation(source).blocks[0].hasLinks)
        value.setAttributes([.font: NSFont.systemFont(ofSize: 14)], range: NSRange(location: 0, length: value.length))
        assertEquivalent(source)
        XCTAssertTrue(ChatLayerMessageTextPresentation(source).nativeFeatures.isEmpty)
        XCTAssertFalse(ChatLayerMessageTextPresentation(source).blocks[0].hasLinks)
        value.mutableString.setString("")
        assertEquivalent(source)
        XCTAssertTrue(ChatLayerMessageTextPresentation(source).nativeFeatures.isEmpty)
    }
}
