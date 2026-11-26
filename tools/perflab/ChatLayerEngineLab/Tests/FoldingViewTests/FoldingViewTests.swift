import Cocoa
import XCTest
import TGUIKit
@testable import FoldingViewHarness

final class FoldingViewTests: XCTestCase {
    override func setUp() { TGUIKitTestBootstrap.install() }

    func content(_ count: Int, quoted: Bool = false) -> (NSAttributedString, [TextViewLayout], [NSRange]) {
        let full = NSMutableAttributedString()
        var blocks: [TextViewLayout] = [], ranges: [NSRange] = []
        for index in 0..<count {
            let value = NSMutableAttributedString(string: "Block \(index) hello مرحبا 👩🏽‍💻\n", attributes: [.font: NSFont.systemFont(ofSize: 14), .foregroundColor: NSColor.black])
            if quoted && index % 2 == 0 {
                value.addAttribute(TextInputAttributes.quote, value: TextViewBlockQuoteData(id: index, colors: .init(main: .blue)), range: value.range)
            }
            ranges.append(NSRange(location: full.length, length: value.length))
            full.append(value)
            blocks.append(TextViewLayout(value))
        }
        return (full, blocks, ranges)
    }
    func layout(_ count: Int, quoted: Bool = false, streaming: Bool = false) -> FoldingTextLayout {
        let (full, blocks, ranges) = content(count, quoted: quoted)
        let result = FoldingTextLayout(attributedString: full, blocks: blocks, blockRanges: ranges, context: BlockContext(), revealed: [], appendingAnimation: streaming)
        result.measure(width: 240)
        return result
    }
    func legacy(_ count: Int, quoted: Bool = false, streaming: Bool = false) -> LegacyFoldingTextLayout {
        let (full, blocks, ranges) = content(count, quoted: quoted)
        let result = LegacyFoldingTextLayout(attributedString: full, blocks: blocks, blockRanges: ranges, context: BlockContext(), revealed: [], appendingAnimation: streaming)
        result.measure(width: 240)
        return result
    }

    func testNewAndReplacedBlocksRespectInteractionSettings() {
        let view = FoldingTextView(frame: .zero)
        view.textSelectable = false
        view.update(layout: layout(2), animated: false)
        XCTAssertTrue(view.textViews.allSatisfy { !$0.isSelectable })
        view.userInteractionEnabled = false
        XCTAssertTrue(view.textViews.allSatisfy { !$0.userInteractionEnabled })
        view.update(layout: layout(4, quoted: true), animated: false)
        XCTAssertEqual(view.textViews.count, 4)
        XCTAssertTrue(view.textViews.allSatisfy { !$0.isSelectable && !$0.userInteractionEnabled })
        view.textSelectable = true
        view.userInteractionEnabled = true
        XCTAssertTrue(view.textViews.allSatisfy { $0.isSelectable && $0.userInteractionEnabled })
    }

    func testEndingStreamingRemovesOwnedDotsWithoutAnExplicitArgument() {
        let view = FoldingTextView(frame: .zero)
        view.update(layout: layout(1, streaming: true), animated: false)
        let dots = view.appendingAnimationView
        XCTAssertNotNil(dots)
        XCTAssertTrue(dots?.superview === view)
        view.update(layout: layout(1), animated: false)
        XCTAssertNil(view.appendingAnimationView)
        XCTAssertNil(dots?.superview)
        XCTAssertEqual(view.subviews.count, 1)
        let old = LegacyFoldingTextView(frame: .zero)
        old.update(layout: legacy(1, streaming: true), animated: false)
        old.update(layout: legacy(1), animated: false)
        XCTAssertNotNil(old.appendingAnimationView)
    }
}
