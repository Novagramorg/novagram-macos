import Cocoa
import XCTest
import TGUIKit
import SwiftSignalKit
@testable import FoldingViewHarness
@testable import ChatLayerEngine

final class LiveChatTextBindingTests: XCTestCase {
    override func setUp() { TGUIKitTestBootstrap.install() }
    let fixtures = ChatTextReuseTests()

    func nativeItem(_ id: Int, context: BlockContext, text: String? = nil) -> FoldingViewHarness.ChatMessageItem {
        let item = fixtures.item(id, quoted: true, context: context, text: text)
        (item.textLayout.blocks[0].text.attributedString as! NSMutableAttributedString).addAttribute(TextInputAttributes.formattedDate, value: "date", range: NSRange(location: 0, length: 1))
        return item
    }

    func testPlainMessagesUseOneViewAndReuseTheirLayerNodes() throws {
        for count in [1, 3, 12] {
            let context = BlockContext(), row = LayerChatTextRow(frame: NSRect(x: 0, y: 0, width: 260, height: 600))
            row.bind(fixtures.item(1, count: count, context: context))
            let host = try XCTUnwrap(row.layerText), nodes = host.body.textNodes
            XCTAssertNil(row.text)
            XCTAssertEqual(viewTreeCount(host), 1)
            XCTAssertTrue(host.root === host.body)
            XCTAssertNil(host.body.parent)
            XCTAssertTrue(host.body.scene === host)
            XCTAssertEqual(nodes.count, count)
            let next = fixtures.item(2, count: count, context: context)
            next.textOrigin = NSPoint(x: 9, y: 31)
            row.bind(next)
            XCTAssertTrue(row.layerText === host)
            XCTAssertTrue(zip(nodes, host.body.textNodes).allSatisfy { $0 === $1 })
            XCTAssertEqual(host.frame, row.textFrame(next))
            XCTAssertEqual(row.subviews.count, 1)
            XCTAssertEqual(host.body.textNodes.map { $0.textLayout?.attributedString.string }, next.textLayout.blocks.map { $0.text.attributedString.string })
        }
    }

    func testSameMessageRetainsLocalAndExternalSelectionAcrossLayoutReplacement() throws {
        for external in [false, true] {
            let context = BlockContext(), row = LayerChatTextRow(frame: .zero)
            row.bind(fixtures.item(1, context: context))
            let node = try XCTUnwrap(row.layerText?.body.textNodes.first)
            let range = NSRange(location: 2, length: 5)
            if external { node.setExternalSelection(range) } else { node.setSelection(range) }
            let next = fixtures.item(1, context: context)
            row.bind(next)
            XCTAssertEqual(next.textLayout.blocks[0].text.selectedRange.range, range)
            XCTAssertEqual(node.hasExternalTextSelection, external)
            if external {
                row.layerText?.clearBubbleSelection()
                XCTAssertFalse(next.textLayout.hasSelectedText)
            }
        }
    }

    func testDifferentMessageAndAccountClearSelectionAndCancelCapturedDrag() throws {
        for accountChange in [false, true] {
            let context = BlockContext(), row = LayerChatTextRow(frame: .zero)
            row.bind(fixtures.item(1, context: context, text: "same contents"))
            let host = try XCTUnwrap(row.layerText), node = try XCTUnwrap(host.body.textNodes.first)
            node.setSelection(NSRange(location: 0, length: 4))
            _ = host.handlePointer(.down, at: NSPoint(x: 2, y: 8))
            let next = fixtures.item(accountChange ? 1 : 2, context: accountChange ? BlockContext() : context, text: "same contents")
            row.bind(next)
            _ = host.handlePointer(.dragged, at: NSPoint(x: 80, y: 8))
            _ = host.handlePointer(.up, at: NSPoint(x: 80, y: 8))
            XCTAssertFalse(next.textLayout.hasSelectedText)
        }
    }

    func testSameMessageLayoutReplacementKeepsAnActiveDrag() throws {
        let context = BlockContext(), row = LayerChatTextRow(frame: .zero)
        row.bind(fixtures.item(1, context: context, text: "select these words"))
        let host = try XCTUnwrap(row.layerText)
        XCTAssertTrue(host.handlePointer(.down, at: NSPoint(x: 2, y: 8)))
        row.bind(fixtures.item(1, context: context, text: "select these words"))
        _ = host.handlePointer(.dragged, at: NSPoint(x: 80, y: 8))
        _ = host.handlePointer(.up, at: NSPoint(x: 80, y: 8))
        XCTAssertTrue(try XCTUnwrap(host.body.textNodes.first?.textLayout).selectedRange.hasSelectText)
    }

    func testMutableAttributesChangeRendererWithoutChangingLayoutIdentity() throws {
        let context = BlockContext(), row = LayerChatTextRow(frame: .zero)
        let item = fixtures.item(1, context: context)
        row.bind(item)
        XCTAssertNotNil(row.layerText)
        let text = try XCTUnwrap(item.textLayout.blocks[0].text.attributedString as? NSMutableAttributedString)
        text.addAttribute(TextInputAttributes.spoiler, value: "https://example.com", range: NSRange(location: 0, length: 4))
        row.bind(item)
        XCTAssertNil(row.layerText)
        XCTAssertNotNil(row.text)
        text.removeAttribute(TextInputAttributes.spoiler, range: NSRange(location: 0, length: 4))
        row.bind(item)
        XCTAssertNotNil(row.layerText)
        XCTAssertNil(row.text)
    }

    func testAnimatedRebindingLeavesTheHostFrameForTheLayoutTransition() throws {
        let context = BlockContext(), row = LayerChatTextRow(frame: .zero)
        row.bind(fixtures.item(1, context: context))
        let host = try XCTUnwrap(row.layerText), originalFrame = host.frame
        let next = fixtures.item(1, context: context)
        next.textOrigin = NSPoint(x: 12, y: 90)
        row.bind(next, animated: true)
        XCTAssertTrue(row.layerText === host)
        XCTAssertEqual(host.frame, originalFrame)
        row.bind(next)
        XCTAssertEqual(host.frame, row.textFrame(next))
    }

    func testExplicitIncomingSelectionWinsOverPreviousSelection() throws {
        let context = BlockContext(), row = LayerChatTextRow(frame: .zero)
        row.bind(fixtures.item(1, context: context))
        row.layerText?.body.textNodes.first?.setSelection(NSRange(location: 0, length: 4))
        let next = fixtures.item(1, context: context)
        let range = NSRange(location: 5, length: 2)
        next.textLayout.blocks[0].text.selectedRange.range = range
        row.bind(next)
        XCTAssertEqual(row.layerText?.body.textNodes.first?.textLayout?.selectedRange.range, range)
    }

    func testNativeFallbacksAndPlainReentry() throws {
        for mode in 0..<5 {
            let context = BlockContext(), row = LayerChatTextRow(frame: .zero)
            row.bind(fixtures.item(1, context: context))
            let oldHost = try XCTUnwrap(row.layerText)
            let next = fixtures.item(2, quoted: mode == 0, context: context, streaming: mode == 1, text: mode == 0 ? "one\ntwo\nthree\nfour\nfive\nsix" : nil, collapsable: mode == 0)
            if mode == 0 {
                try XCTUnwrap(next.textLayout.blocks[0].text.attributedString as? NSMutableAttributedString).addAttribute(TextInputAttributes.quote, value: NSNull(), range: NSRange(location: 0, length: 4))
            } else if mode == 2 {
                try XCTUnwrap(next.textLayout.blocks[0].text.attributedString as? NSMutableAttributedString).addAttribute(TextInputAttributes.formattedDate, value: "date", range: NSRange(location: 0, length: 4))
            } else if mode == 3 {
                try XCTUnwrap(next.textLayout.blocks[0].text.attributedString as? NSMutableAttributedString).addAttribute(TextInputAttributes.spoiler, value: true, range: NSRange(location: 0, length: 4))
            } else if mode == 4 { next.papercutLayout = true }
            row.bind(next)
            XCTAssertNil(row.layerText, "mode=\(mode)")
            XCTAssertNil(oldHost.superview)
            XCTAssertTrue(oldHost.isEventLess)
            if mode != 4 { XCTAssertNotNil(row.text) }
            row.bind(fixtures.item(3, context: context))
            if mode == 1 {
                XCTAssertNotNil(row.text)
                row.bind(fixtures.item(4, context: context))
            }
            XCTAssertNotNil(row.layerText, "mode=\(mode)")
            XCTAssertNil(row.text)
        }
    }

    func testSelectedAndAnimatedNativeTextKeepsNativeRenderingUntilItCanMigrate() throws {
        let context = BlockContext(), row = LayerChatTextRow(frame: .zero)
        row.bind(nativeItem(1, context: context, text: "unchanged"))
        let native = try XCTUnwrap(row.text)
        native.textViews[0].textLayout?.selectedRange.range = NSRange(location: 0, length: 4)
        row.bind(fixtures.item(1, context: context, text: "unchanged"))
        XCTAssertTrue(row.text === native)
        XCTAssertNil(row.layerText)
        native.textViews[0].textLayout?.clearSelect()
        row.bind(fixtures.item(1, context: context, text: "unchanged"), animated: true)
        XCTAssertTrue(row.text === native)
        native.layer?.removeAllAnimations()
        native.textViews.forEach { $0.layer?.removeAllAnimations() }
        row.bind(fixtures.item(1, context: context, text: "unchanged"))
        XCTAssertNil(row.text)
        XCTAssertNotNil(row.layerText)
    }

    func testCallbackRebindingDuringLayerRemovalKeepsTheNewestHost() throws {
        let context = BlockContext(), row = LayerChatTextRow(frame: .zero)
        row.bind(fixtures.item(1, context: context))
        let node = try XCTUnwrap(row.layerText?.body.textNodes.first)
        node.setExternalSelection(NSRange(location: 0, length: 4))
        let newest = fixtures.item(3, context: context)
        node.onSelectionChanged = { _ in
            node.onSelectionChanged = nil
            row.bind(newest)
        }
        row.bind(nativeItem(2, context: context))
        XCTAssertTrue(row.item === newest)
        XCTAssertNil(row.text)
        XCTAssertTrue(row.layerText?.body.textNodes.first?.textLayout === newest.textLayout.blocks[0].text)
        XCTAssertEqual(row.subviews.count, 1)
        XCTAssertFalse(row.layerText?.isEventLess ?? true)
    }

    func testPendingMenuDisposalCannotReplaceANewerRowBinding() throws {
        let context = BlockContext(), row = LayerChatTextRow(frame: .zero)
        let old = fixtures.item(1, context: context)
        old.textLayout.blocks[0].text.alwaysStaticItems = false
        let newest = fixtures.item(3, context: context)
        var cancelled = 0
        old.textLayout.blocks[0].text.interactions.topWindow = {
            Signal { _ in ActionDisposable {
                cancelled += 1
                row.bind(newest)
            } }
        }
        row.bind(old)
        let node = try XCTUnwrap(row.layerText?.body.textNodes.first)
        let event = try XCTUnwrap(NSEvent.mouseEvent(with: .rightMouseDown, location: NSPoint(x: 5, y: 5), modifierFlags: [], timestamp: 0, windowNumber: 0, context: nil, eventNumber: 1, clickCount: 1, pressure: 0))
        XCTAssertTrue(node.requestMenu(at: NSPoint(x: 5, y: 5), event: event))
        row.bind(nativeItem(2, context: context))
        XCTAssertEqual(cancelled, 1)
        XCTAssertTrue(row.item === newest)
        XCTAssertNil(row.text)
        XCTAssertTrue(row.layerText?.body.textNodes.first?.textLayout === newest.textLayout.blocks[0].text)
        XCTAssertEqual(row.subviews.count, 1)
    }

    final class CursorWindow: Window {
        var cursorPoint = NSPoint.zero
        override var mouseLocationOutsideOfEventStream: NSPoint { cursorPoint }
    }

    func testNativePendingMenuCancellationCannotInstallSupersededText() throws {
        let context = BlockContext(), row = LayerChatTextRow(frame: NSRect(x: 0, y: 0, width: 300, height: 200))
        let window = CursorWindow(contentRect: row.bounds, styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = row
        defer { window.contentView = nil; window.close() }
        let old = nativeItem(1, context: context)
        let newest = fixtures.item(3, context: context)
        var started = 0, cancelled = 0
        old.textLayout.blocks[0].text.alwaysStaticItems = false
        old.textLayout.blocks[0].text.interactions.topWindow = {
            Signal { _ in
                started += 1
                return ActionDisposable {
                    cancelled += 1
                    row.bind(newest)
                }
            }
        }
        row.bind(old)
        let native = try XCTUnwrap(row.text?.textViews.first)
        window.cursorPoint = native.convert(NSPoint(x: 5, y: 5), to: nil)
        let event = try XCTUnwrap(NSEvent.mouseEvent(with: .rightMouseDown, location: window.cursorPoint, modifierFlags: [], timestamp: 0, windowNumber: window.windowNumber, context: nil, eventNumber: 1, clickCount: 1, pressure: 0))
        native.rightMouseDown(with: event)
        XCTAssertEqual(started, 1)
        old.textLayout.blocks[0].text.clearSelect()
        row.bind(nativeItem(2, context: context))
        XCTAssertEqual(cancelled, 1)
        XCTAssertTrue(row.item === newest)
        XCTAssertNil(row.text)
        XCTAssertTrue(row.layerText?.body.textNodes.first?.textLayout === newest.textLayout.blocks[0].text)
        XCTAssertEqual(row.subviews.count, 1)
    }

    func testNativeCleanupCallbackCannotOverwriteANewerLayerBinding() throws {
        let context = BlockContext(), row = LayerChatTextRow(frame: .zero)
        let old = nativeItem(1, context: context)
        row.bind(old)
        let newest = fixtures.item(3, context: context)
        var rebound = false
        old.textLayout.blocks[0].text.interactions.hoverOnLink = { _ in
            if !rebound {
                rebound = true
                row.bind(newest)
            }
        }
        row.bind(nativeItem(2, context: context))
        XCTAssertTrue(rebound)
        XCTAssertTrue(row.item === newest)
        XCTAssertNil(row.text)
        XCTAssertTrue(row.layerText?.body.textNodes.first?.textLayout === newest.textLayout.blocks[0].text)
        XCTAssertEqual(row.subviews.count, 1)
    }

    func testLiveSelectionSourcesCombineCaptionsBodyAndWebpageInNativeOrder() throws {
        let context = BlockContext()
        let window = Window(contentRect: NSRect(x: 0, y: 0, width: 300, height: 300), styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        defer { window.contentView = nil; window.close() }
        func makeRow(_ index: Int, layered: Bool) -> ChatTextRow {
            let row: ChatTextRow = layered ? LayerChatTextRow(frame: .zero) : PreviousNativeChatTextRow(frame: .zero)
            let item = fixtures.item(index, context: context, text: "body 👩🏽‍💻 \(index)")
            item.textOrigin = NSPoint(x: 8, y: 30)
            row.bind(item)
            row.header = "Author \(index)"
            func text(_ string: String, y: CGFloat) -> TextView {
                let layout = TextViewLayout(NSAttributedString(string: string, attributes: [.font: NSFont.systemFont(ofSize: 14)]))
                layout.measure(width: 260)
                let view = TextView()
                view.update(layout)
                view.setFrameOrigin(NSPoint(x: 8, y: y))
                row.addSubview(view)
                return view
            }
            row.nativeCaptions = [text("caption \(index)", y: 2)]
            let webpage = ChatTextWebpage()
            webpage.selectableTextViews = [text("webpage \(index)", y: 62)]
            row.webpageContent = webpage
            return row
        }
        for reversedTable in [false, true] {
            let referenceRows = (0..<3).map { makeRow($0, layered: false) }
            let currentRows = (0..<3).map { makeRow($0, layered: $0 != 1) }
            for row in currentRows { XCTAssertEqual(row.textSelectionSources.count, 3) }
            let reference = ReferenceEmbeddedSelectionLoopHarness(SelectionTable(views: referenceRows, reversed: reversedTable))
            let current = SelectionLoopHarness(SelectionTable(views: currentRows, reversed: reversedTable))
            for (begin, end) in [(NSPoint.zero, NSPoint(x: 299, y: 299)), (NSPoint(x: 20, y: 36), NSPoint(x: 80, y: 268))] {
                for reversed in [false, true] {
                    reference.select(begin: reversed ? end : begin, end: reversed ? begin : end, window: window, reversedTable: reversedTable)
                    current.select(begin: reversed ? end : begin, end: reversed ? begin : end, window: window, reversedTable: reversedTable)
                    XCTAssertTrue(current.selectManager.selectedText.isEqual(to: reference.selectManager.selectedText))
                }
            }
        }
    }

    func testBaselineAndClickGeometryMatchNativeTextAtDifferentOrigins() throws {
        let context = BlockContext()
        for count in [1, 3] {
            let native = ReusedChatTextRow(frame: NSRect(x: 0, y: 0, width: 300, height: 400))
            let current = LayerChatTextRow(frame: native.frame)
            let old = fixtures.item(1, count: count, context: context), next = fixtures.item(1, count: count, context: context)
            old.textOrigin = NSPoint(x: 13, y: 29); next.textOrigin = old.textOrigin
            native.bind(old); current.bind(next)
            let nativeText = try XCTUnwrap(native.text), layerText = try XCTUnwrap(current.layerText)
            let first = try XCTUnwrap(nativeText.textViews.first), line = try XCTUnwrap(first.textLayout?.lines.first)
            XCTAssertEqual(current.firstTextBaseline(in: current), first.convert(NSPoint(x: line.frame.minX, y: line.frame.minY), to: native))
            for y in stride(from: CGFloat(-4), through: layerText.bounds.height + 4, by: 4) {
                for x in stride(from: CGFloat(-4), through: 260, by: 4) {
                    let point = NSPoint(x: x, y: y)
                    XCTAssertEqual(layerText.clickInContent(point: point), nativeText.clickInContent(point: point))
                }
            }
        }
    }

    func testPlainMessagePixelsMatchNativeAtBothScales() throws {
        let context = BlockContext()
        var comparisons = 0
        for scale: CGFloat in [1, 2] {
            for count in [1, 3] {
                for text in ["ordinary message", "مرحبا بالعالم", "hello 👩🏽‍💻 café\nsecond line"] {
                    let native = ReusedChatTextRow(frame: NSRect(x: 0, y: 0, width: 270, height: 300))
                    let current = LayerChatTextRow(frame: native.frame)
                    native.bind(fixtures.item(1, count: count, context: context, text: text))
                    current.bind(fixtures.item(1, count: count, context: context, text: text))
                    let lhs = ViewSnapshot.render(native, scale: scale), rhs = ViewSnapshot.render(current, scale: scale)
                    if lhs != rhs {
                        try lhs.write(to: URL(fileURLWithPath: "/tmp/live-native-\(scale)-\(count).png"))
                        try rhs.write(to: URL(fileURLWithPath: "/tmp/live-layers-\(scale)-\(count).png"))
                        for pixel in 0..<(lhs.width * lhs.height) where Array(lhs.bytes[(pixel * 4)..<(pixel * 4 + 4)]) != Array(rhs.bytes[(pixel * 4)..<(pixel * 4 + 4)]) {
                            print("PIXEL", scale, count, pixel % lhs.width, pixel / lhs.width, Array(lhs.bytes[(pixel * 4)..<(pixel * 4 + 4)]), Array(rhs.bytes[(pixel * 4)..<(pixel * 4 + 4)]))
                        }
                    }
                    XCTAssertEqual(lhs.differingPixels(from: rhs, tolerance: 0), 0, "scale=\(scale) count=\(count) text=\(text)")
                    comparisons += 1
                }
            }
        }
        XCTAssertEqual(comparisons, 12)
    }
}
