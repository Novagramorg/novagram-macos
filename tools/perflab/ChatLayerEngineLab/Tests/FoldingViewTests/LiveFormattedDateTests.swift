import Cocoa
import XCTest
import TGUIKit
@testable import FoldingViewHarness
@testable import ChatLayerEngine

final class LiveFormattedDateTests: XCTestCase {
    override func setUp() { TGUIKitTestBootstrap.install() }

    private func addDate(to text: TextViewLayout, value: Any? = nil) {
        let string = NSMutableAttributedString(attributedString: text.attributedString)
        string.addAttribute(TextInputAttributes.formattedDate, value: value ?? TextViewFormattedDateData(text: "Tomorrow", date: 123), range: NSRange(location: 0, length: min(8, string.length)))
        text.setAttributedString(string)
    }

    func testTypedDatesUseLayersAndMalformedOrOtherUnsupportedFeaturesKeepFallback() throws {
        let context = BlockContext()
        let fixtures = ChatTextReuseTests()
        let item = fixtures.item(1, context: context, text: "Tomorrow after lunch")
        addDate(to: item.textLayout.blocks[0].text)
        let presentation = try XCTUnwrap(ChatLayerMessageTextPresentation.simpleText(item.textLayout))
        XCTAssertTrue(presentation.blocks[0].hasFormattedDates)
        XCTAssertTrue(presentation.nativeFeatures.isEmpty)
        let row = LayerChatTextRow(frame: .zero)
        row.bind(item)
        XCTAssertNotNil(row.layerText)
        XCTAssertNil(row.text)
        for key in [TextInputAttributes.spoiler, TextInputAttributes.customEmoji] {
            let next = fixtures.item(2, context: context, text: "Tomorrow after lunch")
            addDate(to: next.textLayout.blocks[0].text)
            let text = next.textLayout.blocks[0].text.attributedString as! NSMutableAttributedString
            text.addAttribute(key, value: "unsupported", range: NSRange(location: 0, length: 1))
            XCTAssertNil(ChatLayerMessageTextPresentation.simpleText(next.textLayout))
        }
        let malformed = fixtures.item(3, context: context, text: "Tomorrow after lunch")
        addDate(to: malformed.textLayout.blocks[0].text, value: "unsupported")
        XCTAssertNil(ChatLayerMessageTextPresentation.simpleText(malformed.textLayout))
    }

    func testDateBodyPixelsAndViewCountMatchNativeAcrossScalesAndQuotes() throws {
        for scale: CGFloat in [1, 2, 3] {
            for quoted in [false, true] {
                for count in [1, 3] {
                    let context = BlockContext()
                    let fixtures = ChatTextReuseTests()
                    func item() -> FoldingViewHarness.ChatMessageItem {
                        let item = fixtures.item(1, count: count, quoted: quoted, context: context, text: "Tomorrow مرحبا 👩🏽‍💻\nafter lunch")
                        for block in item.textLayout.blocks { addDate(to: block.text) }
                        item.textLayout.measure(width: 240)
                        return item
                    }
                    let native = ReusedChatTextRow(frame: NSRect(x: 0, y: 0, width: 280, height: 360))
                    let current = LayerChatTextRow(frame: native.frame)
                    native.bind(item())
                    current.bind(item())
                    let host = try XCTUnwrap(current.layerText)
                    XCTAssertEqual(viewTreeCount(host), 1)
                    XCTAssertTrue(host.body.textNodes.allSatisfy { $0.accessibilityValue?.hasPrefix("Tomorrow") == true })
                    let a = ViewSnapshot.render(native, scale: scale)
                    let b = ViewSnapshot.render(current, scale: scale)
                    XCTAssertEqual(a.differingPixels(from: b, tolerance: 0), 0)
                    XCTAssertGreaterThan(b.pixels(darkerThan: 200), 0)
                }
            }
        }
    }

    func testDateCaptionsReuseLayerHostsAndClearMetadataForPlainContent() throws {
        let context = BlockContext(), fixtures = CaptionReuseTests()
        let first = fixtures.caption(1, text: "Tomorrow after lunch", context: context)
        addDate(to: first.layout.blocks[0].text)
        let row = LayerCaptionRow(frame: .zero)
        row.bind(FoldingViewHarness.ChatRowItem([first]))
        let host = try XCTUnwrap(row.captionViews[0].layerView)
        XCTAssertEqual(viewTreeCount(host), 1)
        let next = fixtures.caption(2, text: "Plain replacement", context: context)
        row.bind(FoldingViewHarness.ChatRowItem([next]))
        XCTAssertTrue(row.captionViews[0].layerView === host)
        let presentation = try XCTUnwrap(ChatLayerMessageTextPresentation.simpleText(next.layout))
        XCTAssertFalse(presentation.blocks[0].hasFormattedDates)
        XCTAssertEqual(host.body.textNodes[0].accessibilityValue, next.layout.blocks[0].text.attributedString.string)
    }

    func testSameMessageDateReplacementPreservesSelectionAndNativeFallback() throws {
        let context = BlockContext(), fixtures = ChatTextReuseTests()
        let row = LayerChatTextRow(frame: .zero)
        let first = fixtures.item(1, context: context, text: "Tomorrow after lunch")
        addDate(to: first.textLayout.blocks[0].text)
        row.bind(first)
        let host = try XCTUnwrap(row.layerText)
        let range = NSRange(location: 0, length: 8)
        host.body.textNodes[0].setExternalSelection(range)
        let second = fixtures.item(1, context: context, text: "Tomorrow after lunch")
        addDate(to: second.textLayout.blocks[0].text)
        row.bind(second)
        XCTAssertTrue(row.layerText === host)
        XCTAssertEqual(second.textLayout.blocks[0].text.selectedRange.range, range)
        let third = fixtures.item(1, context: context, text: "Tomorrow after lunch")
        addDate(to: third.textLayout.blocks[0].text, value: "unsupported")
        row.bind(third)
        XCTAssertNil(row.layerText)
        XCTAssertNotNil(row.text)
        XCTAssertEqual(third.textLayout.blocks[0].text.selectedRange.range, range)
    }
}
