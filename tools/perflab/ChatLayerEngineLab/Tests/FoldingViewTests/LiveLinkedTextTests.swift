import Cocoa
import XCTest
import TGUIKit
import SwiftSignalKit
@testable import FoldingViewHarness
@testable import ChatLayerEngine

final class LiveLinkedTextTests: XCTestCase {
    let factory = ChatTextReuseTests()
    override func setUp() { TGUIKitTestBootstrap.install() }

    func testPlainLinkedAndQuotedTransitionsReuseOrReplaceTheCorrectRenderer() throws {
        let context = BlockContext(), row = LayerChatTextRow(frame: .zero)
        row.bind(factory.item(1, context: context))
        let host = try XCTUnwrap(row.layerText), node = try XCTUnwrap(host.body.textNodes.first)
        var opened: [String] = []
        let linked = factory.item(2, context: context, linked: true)
        linked.textLayout.blocks[0].text.interactions.processURL = { opened.append($0 as! String) }
        row.bind(linked)
        XCTAssertTrue(row.layerText === host)
        XCTAssertTrue(host.body.textNodes.first === node)
        XCTAssertNil(row.text)
        XCTAssertEqual(viewTreeCount(host), 1)
        XCTAssertTrue(host.handlePointer(.down, at: NSPoint(x: 2, y: 5)))
        XCTAssertTrue(host.handlePointer(.up, at: NSPoint(x: 2, y: 5)))
        XCTAssertEqual(opened, ["https://example.com/2/0"])
        row.bind(factory.item(3, context: context))
        _ = host.handlePointer(.down, at: NSPoint(x: 2, y: 5))
        _ = host.handlePointer(.up, at: NSPoint(x: 2, y: 5))
        XCTAssertEqual(opened.count, 1)
        row.bind(factory.item(4, quoted: true, context: context, linked: true))
        XCTAssertTrue(row.layerText === host)
        XCTAssertTrue(host.body.textNodes.first === node)
        XCTAssertNil(row.text)
        row.bind(factory.item(5, context: context, linked: true))
        XCTAssertNotNil(row.layerText)
        XCTAssertNil(row.text)
    }

    func testMutableLinkEligibilityAndClickTargetsAreRescanned() throws {
        let context = BlockContext(), row = LayerChatTextRow(frame: .zero)
        let item = factory.item(1, context: context)
        row.bind(item)
        let host = try XCTUnwrap(row.layerText)
        let text = try XCTUnwrap(item.textLayout.blocks[0].text.attributedString as? NSMutableAttributedString)
        var opened = 0
        item.textLayout.blocks[0].text.interactions.processURL = { _ in opened += 1 }
        for linked in [true, false, true] {
            if linked { text.addAttribute(.link, value: "target", range: NSRange(location: 0, length: 4)) }
            else { text.removeAttribute(.link, range: NSRange(location: 0, length: 4)) }
            row.bind(item)
            XCTAssertTrue(row.layerText === host)
            let before = opened
            _ = host.handlePointer(.down, at: NSPoint(x: 2, y: 5))
            _ = host.handlePointer(.up, at: NSPoint(x: 2, y: 5))
            XCTAssertEqual(opened - before, linked ? 1 : 0)
        }
    }

    func testMessageReuseCancelsPreviewAndAnOldLinkPress() throws {
        let context = BlockContext(), row = LayerChatTextRow(frame: .zero)
        let item = factory.item(1, context: context, linked: true)
        let ready = expectation(description: "Preview started")
        var disposed = 0, opened = 0
        item.textLayout.blocks[0].text.interactions.longHoverOnLink = { _, _ in
            ready.fulfill()
            return ActionDisposable { disposed += 1 }
        }
        row.bind(item)
        let host = try XCTUnwrap(row.layerText)
        _ = host.handlePointer(.moved, at: NSPoint(x: 2, y: 5))
        wait(for: [ready], timeout: 3)
        _ = host.handlePointer(.down, at: NSPoint(x: 2, y: 5))
        let next = factory.item(2, context: context, linked: true)
        next.textLayout.blocks[0].text.interactions.processURL = { _ in opened += 1 }
        row.bind(next)
        _ = host.handlePointer(.up, at: NSPoint(x: 2, y: 5))
        XCTAssertEqual(disposed, 1)
        XCTAssertEqual(opened, 0)
    }

    func testLinkedTextPixelsAndBaselineMatchNativeIncludingSelection() throws {
        let context = BlockContext()
        for count in [1, 3] {
            for scale: CGFloat in [1, 2] {
                for selected in [false, true] {
                    for text in ["linked message", "مرحبا بالعالم", "hello 👩🏽‍💻 café\nsecond line"] {
                        let native = ReusedChatTextRow(frame: NSRect(x: 0, y: 0, width: 270, height: 300))
                        let current = LayerChatTextRow(frame: native.frame)
                        for row: ChatTextRow in [native, current] {
                            let item = factory.item(1, count: count, context: context, text: text, linked: true)
                            item.textOrigin = NSPoint(x: 13, y: 29)
                            row.bind(item)
                            if selected { item.textLayout.blocks[0].text.selectedRange.range = NSRange(location: 1, length: 7) }
                        }
                        let host = try XCTUnwrap(current.layerText)
                        let reference = try XCTUnwrap(native.text)
                        let first = try XCTUnwrap(reference.textViews.first), line = try XCTUnwrap(first.textLayout?.lines.first)
                        XCTAssertEqual(current.firstTextBaseline(in: current), first.convert(NSPoint(x: line.frame.minX, y: line.frame.minY), to: native))
                        XCTAssertEqual(viewTreeCount(host), 1)
                        let lhs = ViewSnapshot.render(native, scale: scale), rhs = ViewSnapshot.render(current, scale: scale)
                        XCTAssertEqual(lhs.differingPixels(from: rhs, tolerance: 0), 0, "count=\(count) scale=\(scale) selected=\(selected) text=\(text)")
                    }
                }
            }
        }
    }
}
