import AppKit
import XCTest
@testable import TGUIKit

final class TextNodeLineLimitTests: XCTestCase {
    override func setUp() {
        super.setUp()
        TGUIKitTestBootstrap.install()
    }

    func testNonpositiveLimitsUseUnlimitedLayoutWithoutOverflow() {
        let text = NSAttributedString(string: "several words across several lines\nand a second paragraph 👩🏽‍💻", attributes: [.font: NSFont.systemFont(ofSize: 14), .foregroundColor: NSColor.black, .selectedColor: NSColor.red])
        for value: NSAttributedString? in [nil, NSAttributedString(string: ""), text] {
            for selected in [false, true] {
                let size = CGSize(width: 90, height: 400)
                let expected = TextNode.layoutText(value, nil, 0, .end, size, nil, selected, .left).0
                for limit in [Int.min, -1, 0] {
                    let actual = TextNode.layoutText(value, nil, limit, .end, size, nil, selected, .left).0
                    XCTAssertEqual(actual.size, expected.size)
                    XCTAssertEqual(actual.numberOfLines, expected.numberOfLines)
                    XCTAssertEqual(actual.firstLineWidth, expected.firstLineWidth)
                }
            }
        }
    }

    func testSwitchingLineLimitsRemeasuresAndThenReusesLayout() {
        let text = NSAttributedString(string: String(repeating: "long message text ", count: 8), attributes: [.font: NSFont.systemFont(ofSize: 14), .foregroundColor: NSColor.black])
        let size = CGSize(width: 90, height: 400)
        let single = TextNode.layoutText(text, nil, 1, .end, size, nil, false, .left)
        XCTAssertEqual(single.0.numberOfLines, 1)
        let unlimited = TextNode.layoutText(maybeNode: single.1, text, nil, Int.min, .end, size, nil, false, .left)
        XCTAssertFalse(single.0 === unlimited.0)
        XCTAssertGreaterThan(unlimited.0.numberOfLines, 1)
        let repeated = TextNode.layoutText(maybeNode: single.1, text, nil, Int.min, .end, size, nil, false, .left)
        XCTAssertTrue(unlimited.0 === repeated.0)
        let restored = TextNode.layoutText(maybeNode: single.1, text, nil, 1, .end, size, nil, false, .left)
        XCTAssertEqual(restored.0.size, single.0.size)
        XCTAssertEqual(restored.0.numberOfLines, single.0.numberOfLines)
    }
}
