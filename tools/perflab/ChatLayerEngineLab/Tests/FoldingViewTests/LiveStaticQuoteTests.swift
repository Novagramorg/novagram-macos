import Cocoa
import XCTest
import TGUIKit
@testable import FoldingViewHarness
@testable import ChatLayerEngine

final class LiveStaticQuoteTests: XCTestCase {
    override func setUp() { TGUIKitTestBootstrap.install() }
    let fixtures = ChatTextReuseTests()
    func testStaticQuotePixelsAndViewCounts() throws {
        let context = BlockContext()
        for scale: CGFloat in [1, 2, 3] {
            for count in [1, 3] {
                for text in ["quoted message", "مرحبا بالعالم", "hello 👩🏽‍💻 café\nsecond line"] {
                    let native = ReusedChatTextRow(frame: NSRect(x: 0, y: 0, width: 280, height: 360))
                    let current = LayerChatTextRow(frame: native.frame)
                    native.bind(fixtures.item(1, count: count, quoted: true, context: context, text: text))
                    current.bind(fixtures.item(1, count: count, quoted: true, context: context, text: text))
                    let host = try XCTUnwrap(current.layerText)
                    XCTAssertEqual(viewTreeCount(host), 1)
                    XCTAssertNil(current.text)
                    let a = ViewSnapshot.render(native, scale: scale)
                    let b = ViewSnapshot.render(current, scale: scale)
                    XCTAssertEqual(a.differingPixels(from: b, tolerance: 0), 0, "\(scale)x, \(count) blocks, \(text)")
                    XCTAssertGreaterThan(b.pixels(darkerThan: 200), 0)
                }
            }
        }
    }
    func testStaticQuoteBaselineAndClickGeometry() throws {
        let context = BlockContext()
        for count in [1, 3] {
            let native = ReusedChatTextRow(frame: NSRect(x: 0, y: 0, width: 300, height: 400))
            let current = LayerChatTextRow(frame: native.frame)
            let old = fixtures.item(1, count: count, quoted: true, context: context)
            let next = fixtures.item(1, count: count, quoted: true, context: context)
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
    func testStaticQuoteReusesAndClearsSelectionForAnotherMessage() throws {
        let context = BlockContext(), row = LayerChatTextRow(frame: .zero)
        row.bind(fixtures.item(1, count: 3, quoted: true, context: context))
        let host = try XCTUnwrap(row.layerText), first = host.body.textNodes[0]
        first.setExternalSelection(NSRange(location: 0, length: 5))
        row.bind(fixtures.item(2, count: 3, quoted: true, context: context))
        XCTAssertTrue(row.layerText === host)
        XCTAssertTrue(host.body.textNodes[0] === first)
        XCTAssertEqual(first.textLayout?.selectedRange.range.location, NSNotFound)
        XCTAssertFalse(first.hasExternalTextSelection)
    }
    func testCodeHeadersAndSelectedQuotesMatchNative() throws {
        let context = BlockContext()
        for scale: CGFloat in [1, 2, 3] {
            for code in [false, true] {
                for selected in [false, true] {
                    func item() -> FoldingViewHarness.ChatMessageItem {
                        let item = fixtures.item(1, count: 3, quoted: true, context: context, text: "quoted مرحبا\nlet answer = 42")
                        let header = code ? TextNode.layoutText(NSAttributedString(string: "Swift", attributes: [.font: NSFont.systemFont(ofSize: 12), .foregroundColor: NSColor.blue]), nil, 1, .end, NSSize(width: 200, height: 40), nil, false, .left) : nil
                        let quote = TextViewBlockQuoteData(id: 0, colors: .init(main: .blue, secondary: .red, tertiary: .green), isCode: code, header: header)
                        for block in item.textLayout.blocks where block.text.hasBlockQuotes {
                            let value = NSMutableAttributedString(attributedString: block.text.attributedString)
                            value.addAttribute(TextInputAttributes.quote, value: quote, range: value.range)
                            block.text.setAttributedString(value)
                        }
                        item.textLayout.measure(width: 240)
                        if selected {
                            for block in item.textLayout.blocks { block.text.selectedRange.range = NSRange(location: 1, length: 5) }
                        }
                        return item
                    }
                    let native = ReusedChatTextRow(frame: NSRect(x: 0, y: 0, width: 280, height: 360))
                    let current = LayerChatTextRow(frame: native.frame)
                    native.bind(item()); current.bind(item())
                    XCTAssertNotNil(current.layerText)
                    let before = ViewSnapshot.render(native, scale: scale)
                    let after = ViewSnapshot.render(current, scale: scale)
                    XCTAssertEqual(before.differingPixels(from: after, tolerance: 0), 0, "code=\(code), selected=\(selected), scale=\(scale)")
                }
            }
        }
    }
    func testCollapsibleQuotesKeepLayerRenderingAndRecover() {
        let context = BlockContext(), row = LayerChatTextRow(frame: .zero)
        row.bind(fixtures.item(1, quoted: true, context: context))
        XCTAssertNotNil(row.layerText)
        row.bind(fixtures.item(2, quoted: true, context: context, text: "one\ntwo\nthree\nfour\nfive\nsix", collapsable: true))
        XCTAssertNotNil(row.layerText)
        XCTAssertNil(row.text)
        row.bind(fixtures.item(3, quoted: true, context: context))
        XCTAssertNotNil(row.layerText)
        XCTAssertNil(row.text)
    }

    func testQuotedCrossRowCopyMatchesNative() throws {
        let context = BlockContext()
        let window = Window(contentRect: NSRect(x: 0, y: 0, width: 300, height: 300), styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        defer { window.contentView = nil; window.close() }
        func makeRow(_ index: Int, layered: Bool) -> ChatTextRow {
            let row: ChatTextRow = layered ? LayerChatTextRow(frame: .zero) : PreviousNativeChatTextRow(frame: .zero)
            let item = fixtures.item(index, quoted: true, context: context, text: "body 👩🏽‍💻 \(index)")
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

    func testQuotedLinkPixelsAndBaselineMatchNativeIncludingSelection() throws {
        let context = BlockContext()
        for count in [1, 3] {
            for scale: CGFloat in [1, 2] {
                for selected in [false, true] {
                    for text in ["linked message", "مرحبا بالعالم", "hello 👩🏽‍💻 café\nsecond line"] {
                        let native = ReusedChatTextRow(frame: NSRect(x: 0, y: 0, width: 270, height: 300))
                        let current = LayerChatTextRow(frame: native.frame)
                        for row: ChatTextRow in [native, current] {
                            let item = fixtures.item(1, count: count, quoted: true, context: context, text: text, linked: true)
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
    func testQuotedLinksDispatchCurrentTargetAndCancelCapturedPress() throws {
        let context = BlockContext(), row = LayerChatTextRow(frame: .zero)
        var opened: [String] = []
        func item(_ id: Int) -> FoldingViewHarness.ChatMessageItem {
            let item = fixtures.item(id, quoted: true, context: context, linked: true)
            item.textLayout.blocks[0].text.interactions.processURL = { opened.append($0 as! String) }
            return item
        }
        row.bind(item(1))
        let host = try XCTUnwrap(row.layerText), node = host.body.textNodes[0]
        let line = try XCTUnwrap(node.textLayout?.lines.first)
        let point = NSPoint(x: line.frame.minX + 2, y: line.frame.midY)
        XCTAssertTrue(host.handlePointer(.down, at: point))
        XCTAssertTrue(host.handlePointer(.up, at: point))
        XCTAssertEqual(opened, ["https://example.com/1/0"])
        XCTAssertTrue(host.handlePointer(.down, at: point))
        row.bind(item(2))
        _ = host.handlePointer(.up, at: point)
        XCTAssertEqual(opened.count, 1)
        XCTAssertTrue(row.layerText === host)
        XCTAssertTrue(host.handlePointer(.down, at: point))
        XCTAssertTrue(host.handlePointer(.up, at: point))
        XCTAssertEqual(opened, ["https://example.com/1/0", "https://example.com/2/0"])
        XCTAssertEqual(node.accessibilityValue as? String, node.textLayout?.attributedString.string)
    }

    func testCodeHeaderCopyUsesCurrentMessageAndDisappearsForPlainText() throws {
        let context = BlockContext(), row = LayerChatTextRow(frame: .zero)
        var copied: [String] = []
        func item(_ id: Int) -> FoldingViewHarness.ChatMessageItem {
            let item = fixtures.item(id, quoted: true, context: context, text: "let value = \(id)")
            let layout = item.textLayout.blocks[0].text
            let title = TextNode.layoutText(NSAttributedString(string: "Swift", attributes: [.font: NSFont.systemFont(ofSize: 12)]), nil, 1, .end, NSSize(width: 200, height: 40), nil, false, .left)
            let value = NSMutableAttributedString(attributedString: layout.attributedString)
            value.addAttribute(TextInputAttributes.quote, value: TextViewBlockQuoteData(id: 0, colors: .init(main: .blue), isCode: true, header: title), range: value.range)
            layout.setAttributedString(value)
            layout.interactions.copyToClipboard = { copied.append($0) }
            item.textLayout.measure(width: 240)
            return item
        }
        row.bind(item(1))
        let host = try XCTUnwrap(row.layerText), node = host.body.textNodes[0]
        let header = try XCTUnwrap(node.children.first)
        let point = NSPoint(x: header.frame.midX, y: header.frame.midY)
        XCTAssertTrue(host.handlePointer(.down, at: point))
        XCTAssertTrue(host.handlePointer(.up, at: point))
        row.bind(item(2))
        XCTAssertTrue(node.children.first === header)
        XCTAssertTrue(host.handlePointer(.down, at: point))
        XCTAssertTrue(host.handlePointer(.up, at: point))
        XCTAssertEqual(copied, ["let value = 1", "let value = 2"])
        row.bind(fixtures.item(3, context: context))
        XCTAssertTrue(node.children.isEmpty)
        XCTAssertNil(header.scene)
        XCTAssertNil(node.layer.mask)
    }

    func testQuoteReflowKeepsLayerRenderingAcrossFoldingThreshold() throws {
        let context = BlockContext(), row = LayerChatTextRow(frame: .zero)
        let item = fixtures.item(1, quoted: true, context: context, text: "A collapsible quote that becomes longer than three lines when the available width shrinks significantly.", collapsable: true)
        item.textLayout.measure(width: 600)
        row.bind(item)
        XCTAssertNotNil(row.layerText)
        item.textLayout.measure(width: 70)
        row.bind(item)
        XCTAssertNotNil(row.layerText)
        XCTAssertNil(row.text)
        item.textLayout.measure(width: 600)
        row.bind(item)
        XCTAssertNotNil(row.layerText)
        XCTAssertNil(row.text)
    }

    func testMalformedQuoteAttributeRemainsNative() {
        let item = fixtures.item(1, context: BlockContext())
        (item.textLayout.blocks[0].text.attributedString as! NSMutableAttributedString).addAttribute(TextInputAttributes.quote, value: NSNull(), range: NSRange(location: 0, length: 1))
        XCTAssertNil(ChatLayerMessageTextPresentation.simpleText(item.textLayout))
    }

}
