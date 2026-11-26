import Cocoa
import XCTest
@testable import TGUIKit

final class TextQuoteMeasurementTests: XCTestCase {
    override func setUp() { TGUIKitTestBootstrap.install() }

    func testLastNonemptyQuoteDeterminesLineBackground() {
        let text = NSMutableAttributedString(string: "abcdefghijklmnop", attributes: [.font: NSFont.systemFont(ofSize: 14)])
        let first = TextViewBlockQuoteData(id: 1, colors: .init(main: .blue))
        let last = TextViewBlockQuoteData(id: 2, colors: .init(main: .red), isCode: true)
        text.addAttribute(TextInputAttributes.quote, value: first, range: NSRange(location: 2, length: 3))
        text.addAttribute(TextInputAttributes.quote, value: last, range: NSRange(location: 8, length: 2))
        let layout = TextViewLayout(text, maximumNumberOfLines: 0)
        layout.measure(width: 500)
        XCTAssertEqual(layout.lines.count, 1)
        XCTAssertEqual(layout.blockQuotes.count, 1)
        XCTAssertEqual(layout.blockQuotes.first?.colors.main, NSColor.red)
        XCTAssertEqual(layout.blockQuotes.first?.isCode, true)
    }

    func testUnsupportedLastQuotePreservesAbsentBackground() {
        let text = NSMutableAttributedString(string: "abcdefghijklmnop", attributes: [.font: NSFont.systemFont(ofSize: 14)])
        text.addAttribute(TextInputAttributes.quote, value: TextViewBlockQuoteData(id: 1, colors: .init(main: .blue)), range: NSRange(location: 2, length: 3))
        text.addAttribute(TextInputAttributes.quote, value: NSNumber(value: 42), range: NSRange(location: 8, length: 2))
        let layout = TextViewLayout(text, maximumNumberOfLines: 0)
        layout.measure(width: 500)
        XCTAssertEqual(layout.lines.count, 1)
        XCTAssertTrue(layout.blockQuotes.isEmpty)
    }

    func testQuoteRangeCacheDoesNotSurviveRemeasurement() {
        let text = NSMutableAttributedString(string: String(repeating: "one two three ", count: 18), attributes: [.font: NSFont.systemFont(ofSize: 14)])
        let layout = TextViewLayout(text, maximumNumberOfLines: 0)
        layout.measure(width: 150)
        XCTAssertTrue(layout.blockQuotes.isEmpty)
        for offset in [0, 30, 120] {
            text.addAttribute(TextInputAttributes.quote, value: TextViewBlockQuoteData(id: offset, colors: .init(main: .blue)), range: NSRange(location: offset, length: 50))
            layout.measure(width: 150)
            let fresh = TextViewLayout(text.copy() as! NSAttributedString, maximumNumberOfLines: 0)
            fresh.measure(width: 150)
            XCTAssertFalse(layout.blockQuotes.isEmpty)
            XCTAssertEqual(layout.layoutSize, fresh.layoutSize)
            XCTAssertEqual(layout.lines.map(\.frame), fresh.lines.map(\.frame))
            XCTAssertEqual(layout.blockQuotes.map(\.frame), fresh.blockQuotes.map(\.frame))
            XCTAssertEqual(layout.blockQuotes.map(\.range), fresh.blockQuotes.map(\.range))
            text.removeAttribute(TextInputAttributes.quote, range: NSRange(location: 0, length: text.length))
            layout.measure(width: 150)
            XCTAssertTrue(layout.blockQuotes.isEmpty)
        }
    }
}
