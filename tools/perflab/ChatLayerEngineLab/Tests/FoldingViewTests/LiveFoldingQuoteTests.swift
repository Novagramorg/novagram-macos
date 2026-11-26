import Cocoa
import XCTest
import TGUIKit
import InputTextView
@testable import FoldingViewHarness
@testable import ChatLayerEngine

final class LiveFoldingQuoteTests: XCTestCase {
    override func setUp() { TGUIKitTestBootstrap.install() }
    let fixtures = ChatTextReuseTests()
    let text = "First quoted line\nSecond quoted line\nThird quoted line\nFourth quoted line\nLast quoted line"

    func item(_ id: Int, context: BlockContext, revealed: Bool = false, count: Int = 1, text: String? = nil, linked: Bool = false) -> FoldingViewHarness.ChatMessageItem {
        let result = fixtures.item(id, count: count, quoted: true, context: context, text: text ?? self.text, collapsable: true, linked: linked)
        result.textLayout.revealed = revealed ? Set(0..<count) : []
        result.textLayout.measure(width: 240)
        return result
    }
    func clickArrow(_ host: ChatLayerMessageTextView, index: Int = 0) {
        let node = host.body.textNodes[index]
        let point = NSPoint(x: node.frame.maxX - 8, y: node.frame.maxY - 9)
        XCTAssertTrue(host.handlePointer(.down, at: point))
        XCTAssertTrue(host.handlePointer(.up, at: point))
    }
    func finish() {
        let done = expectation(description: "quote transition")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { done.fulfill() }
        wait(for: [done], timeout: 2)
    }
    func testBodyAndCaptionPixelsMatchNative() throws {
        let context = BlockContext()
        var comparisons = 0
        for scale: CGFloat in [1, 2, 3] {
            for value in [text, "مرحبا بالعالم\nQuoted English\nשלום\nمرحبا\nLast line", "中文 日本語\ncafé 👩🏽‍💻 🦆\n한글\nCombining café\nLast line"] {
                for revealed in [false, true] {
                    for count in [1, 3] {
                        func next() -> FoldingViewHarness.ChatMessageItem {
                            item(1, context: context, revealed: revealed, count: count, text: value)
                        }
                        let native = ReusedChatTextRow(frame: NSRect(x: 0, y: 0, width: 280, height: 650))
                        let current = LayerChatTextRow(frame: native.frame)
                        native.bind(next()); current.bind(next())
                        let host = try XCTUnwrap(current.layerText)
                        XCTAssertNil(current.text)
                        XCTAssertEqual(viewTreeCount(host), 1)
                        XCTAssertEqual(host.body.textNodes.count, count)
                        XCTAssertEqual(ViewSnapshot.render(native, scale: scale).differingPixels(from: ViewSnapshot.render(current, scale: scale), tolerance: 0), 0)
                        let nativeCaption = ReusedCaptionRow(frame: native.frame)
                        let layerCaption = LayerCaptionRow(frame: native.frame)
                        for row: CaptionRowEnvironment in [nativeCaption, layerCaption] {
                            row.bind(ChatRowItem([.init(messageId: 1, id: 1, layout: next().textLayout, offset: NSPoint(x: 4, y: 7))]))
                            row.finishLayout()
                        }
                        XCTAssertNotNil(layerCaption.captionViews[0].layerView)
                        XCTAssertEqual(ViewSnapshot.render(nativeCaption, scale: scale).differingPixels(from: ViewSnapshot.render(layerCaption, scale: scale), tolerance: 0), 0)
                        comparisons += 2
                    }
                }
            }
        }
        XCTAssertEqual(comparisons, 72)
    }
    func testRevealDispatchesCurrentMessageAndCancelsCapturedPressOnReuse() throws {
        let context = BlockContext(), row = LayerChatTextRow(frame: .zero)
        let first = item(1, context: context)
        row.bind(first)
        let host = try XCTUnwrap(row.layerText)
        clickArrow(host)
        XCTAssertEqual(first.revealedIndices, [0])
        let node = host.body.textNodes[0]
        let point = NSPoint(x: node.frame.maxX - 8, y: node.frame.maxY - 9)
        XCTAssertTrue(host.handlePointer(.down, at: point))
        let next = item(2, context: context)
        row.bind(next)
        _ = host.handlePointer(.up, at: point)
        XCTAssertTrue(next.revealedIndices.isEmpty)
        XCTAssertTrue(row.layerText === host)
        clickArrow(host)
        XCTAssertEqual(next.revealedIndices, [0])
        XCTAssertEqual(first.revealedIndices, [0])
    }
    func testAnimatedRevealAndImmediateReuseClearObsoleteGeometry() throws {
        let context = BlockContext(), row = LayerChatTextRow(frame: .zero)
        row.bind(item(1, context: context, count: 3))
        let host = try XCTUnwrap(row.layerText), node = host.body.textNodes[0]
        row.bind(item(1, context: context, revealed: true, count: 3), animated: true)
        XCTAssertTrue(row.layerText === host)
        XCTAssertNotNil(node.layer.animation(forKey: "bounds"))
        XCTAssertNotNil(host.body.textNodes[1].layer.animation(forKey: "position"))
        row.bind(item(1, context: context, count: 3), animated: true)
        XCTAssertNil(node.drawingLayer.mask)
        row.bind(item(2, context: context, revealed: true, count: 3))
        XCTAssertNil(node.layer.animation(forKey: "bounds"))
        XCTAssertNil(host.body.textNodes[1].layer.animation(forKey: "position"))
        finish()
        XCTAssertNil(node.drawingLayer.mask)
    }
    func testCaptionReorderingKeepsCurrentRevealIdentityAndAnimation() throws {
        let context = BlockContext(), row = LayerCaptionRow(frame: .zero)
        func caption(_ id: Int, revealed: Bool = false) -> FoldingViewHarness.ChatRowItem.RowCaption {
            .init(messageId: id, id: UInt32(id), layout: item(id, context: context, revealed: revealed).textLayout)
        }
        row.bind(ChatRowItem([caption(1), caption(2)]))
        let first = try XCTUnwrap(row.captionViews[0].layerView), second = try XCTUnwrap(row.captionViews[1].layerView)
        let next = ChatRowItem([caption(2, revealed: true), caption(1)])
        row.bind(next, animated: true)
        row.finishLayout()
        row.contentViews.forEach { $0.layoutSubtreeIfNeeded() }
        XCTAssertTrue(row.captionViews[0].layerView === second)
        XCTAssertTrue(row.captionViews[1].layerView === first)
        XCTAssertNotNil(second.body.textNodes[0].layer.animation(forKey: "bounds"))
        clickArrow(second); clickArrow(first)
        XCTAssertEqual(next.revealed.map { $0.1 }, [2, 1])
        let recycled = ChatRowItem([caption(3)])
        row.bind(recycled)
        let current = try XCTUnwrap(row.captionViews[0].layerView)
        clickArrow(current)
        XCTAssertEqual(recycled.revealed.map { $0.1 }, [3])
        XCTAssertNil(second.body.revealBlockAtIndex)
    }
    func testFallbackPreservesSelectionInSharedLayoutAndClearsOldAction() throws {
        let context = BlockContext(), row = LayerChatTextRow(frame: .zero)
        let current = item(1, context: context)
        row.bind(current)
        let host = try XCTUnwrap(row.layerText)
        let selected = NSRange(location: 1, length: 4)
        host.body.textNodes[0].setExternalSelection(selected)
        let value = current.textLayout.blocks[0].text.attributedString as! NSMutableAttributedString
        value.addAttribute(TextInputAttributes.formattedDate, value: "date", range: selected)
        row.bind(current)
        XCTAssertNil(row.layerText)
        XCTAssertNotNil(row.text)
        XCTAssertEqual(current.textLayout.blocks[0].text.selectedRange.range, selected)
        XCTAssertNil(host.body.revealBlockAtIndex)
        XCTAssertFalse(host.body.textNodes[0].onTextClick?() ?? false)
        value.removeAttribute(TextInputAttributes.formattedDate, range: selected)
        row.bind(current)
        XCTAssertNotNil(row.text)
        current.textLayout.blocks[0].text.clearSelect()
        row.bind(current)
        XCTAssertNotNil(row.layerText)
    }
    func testReentrantRevealCannotRestoreOldMessageOrAnimations() throws {
        let context = BlockContext(), row = LayerChatTextRow(frame: .zero)
        let first = item(1, context: context), next = item(2, context: context, revealed: true)
        first.onReveal = { _ in row.bind(next, animated: true); row.finishLayout() }
        row.bind(first)
        let host = try XCTUnwrap(row.layerText)
        clickArrow(host)
        XCTAssertEqual(first.revealedIndices, [0])
        XCTAssertTrue(row.item === next)
        XCTAssertEqual(host.body.textNodes[0].frame.height, next.textLayout.size.height)
        XCTAssertNil(host.body.textNodes[0].layer.animation(forKey: "bounds"))
        clickArrow(host)
        XCTAssertEqual(next.revealedIndices, [0])
    }
    func testFoldedHostRequiresRevealAction() throws {
        let current = item(1, context: BlockContext())
        let presentation = try XCTUnwrap(ChatLayerMessageTextPresentation.simpleText(current.textLayout))
        XCTAssertTrue(presentation.requiresRevealAction)
        let host = ChatLayerMessageTextView(frame: .zero)
        let identity = ChatLayerMessageTextView.Identity(messageId: 1, accountId: ObjectIdentifier(current.textLayout.context))
        XCTAssertFalse(host.update(presentation, identity: identity))
        XCTAssertTrue(host.body.textNodes.isEmpty)
        host.body.revealBlockAtIndex = { _ in }
        XCTAssertTrue(host.update(presentation, identity: identity))
    }
    func testMovingBetweenScalesPreservesBitmapsAndNativePixels() throws {
        let context = BlockContext()
        for revealed in [false, true] {
            let native = ReusedChatTextRow(frame: NSRect(x: 0, y: 0, width: 280, height: 200))
            let current = LayerChatTextRow(frame: native.frame)
            let model = item(1, context: context, revealed: revealed)
            native.bind(item(1, context: context, revealed: revealed)); current.bind(model)
            let node = try XCTUnwrap(current.layerText?.body.textNodes.first)
            for scale: CGFloat in [1, 3, 2, 1, 2] {
                let before = ViewSnapshot.render(native, scale: scale)
                let after = ViewSnapshot.render(current, scale: scale)
                XCTAssertEqual(before.differingPixels(from: after, tolerance: 0), 0)
                if let expected = model.textLayout.blocks[0].mask {
                    let actual = try XCTUnwrap(node.drawingLayer.mask?.contents)
                    XCTAssertEqual(CFGetTypeID(actual as CFTypeRef), CGImage.typeID)
                    XCTAssertTrue((actual as AnyObject) === expected)
                }
            }
        }
    }
    func testFoldedCodeAndSelectedTextMatchNative() throws {
        let context = BlockContext()
        for scale: CGFloat in [1, 2, 3] {
            for revealed in [false, true] {
                for selected in [false, true] {
                    func code() -> FoldingViewHarness.ChatMessageItem {
                        let model = item(1, context: context, revealed: revealed)
                        let block = model.textLayout.blocks[0].text
                        let header = TextNode.layoutText(NSAttributedString(string: "Swift", attributes: [.font: NSFont.systemFont(ofSize: 12), .foregroundColor: NSColor.blue]), nil, 1, .end, NSSize(width: 200, height: 40), nil, false, .left)
                        let value = NSMutableAttributedString(attributedString: block.attributedString)
                        value.addAttribute(TextInputAttributes.quote, value: TextViewBlockQuoteData(id: 0, colors: .init(main: .blue), isCode: true, header: header, collapsable: true), range: value.range)
                        block.setAttributedString(value)
                        model.textLayout.measure(width: 240)
                        if selected { block.selectedRange.range = NSRange(location: 1, length: 9) }
                        return model
                    }
                    let native = ReusedChatTextRow(frame: NSRect(x: 0, y: 0, width: 280, height: 200))
                    let current = LayerChatTextRow(frame: native.frame)
                    native.bind(code()); current.bind(code())
                    XCTAssertNotNil(current.layerText)
                    XCTAssertEqual(ViewSnapshot.render(native, scale: scale).differingPixels(from: ViewSnapshot.render(current, scale: scale), tolerance: 0), 0)
                }
            }
        }
    }
    func testFoldedLinksAndSelectionDoNotTriggerReveal() throws {
        let context = BlockContext(), row = LayerChatTextRow(frame: .zero)
        let model = item(1, context: context, linked: true)
        var links: [String] = []
        model.textLayout.blocks[0].text.interactions.processURL = { links.append($0 as! String) }
        row.bind(model)
        let host = try XCTUnwrap(row.layerText), node = host.body.textNodes[0]
        let rect = try XCTUnwrap(node.textLayout?.rects(NSRange(location: 0, length: 4)).first?.0)
        let point = NSPoint(x: rect.midX, y: rect.midY)
        XCTAssertTrue(host.handlePointer(.down, at: point)); XCTAssertTrue(host.handlePointer(.up, at: point))
        XCTAssertEqual(links, ["https://example.com/1/0"])
        XCTAssertTrue(model.revealedIndices.isEmpty)
        node.setExternalSelection(NSRange(location: 1, length: 4))
        clickArrow(host)
        XCTAssertTrue(model.revealedIndices.isEmpty)
        clickArrow(host)
        XCTAssertEqual(model.revealedIndices, [0])
    }
    func testFoldedCrossRowSelectionMatchesNative() throws {
        let context = BlockContext()
        let window = Window(contentRect: NSRect(x: 0, y: 0, width: 300, height: 300), styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        defer { window.contentView = nil; window.close() }
        for reversedTable in [false, true] {
            let native = (0..<3).map { id -> ChatTextRow in
                let row = ReusedChatTextRow(frame: .zero)
                row.bind(item(id, context: context)); return row
            }
            let layers = (0..<3).map { id -> ChatTextRow in
                let row = LayerChatTextRow(frame: .zero)
                row.bind(item(id, context: context)); return row
            }
            let reference = ReferenceEmbeddedSelectionLoopHarness(SelectionTable(views: native, reversed: reversedTable))
            let current = SelectionLoopHarness(SelectionTable(views: layers, reversed: reversedTable))
            for pair in [(NSPoint.zero, NSPoint(x: 299, y: 299)), (NSPoint(x: 20, y: 12), NSPoint(x: 80, y: 268))] {
                for reversed in [false, true] {
                    let begin = reversed ? pair.1 : pair.0, end = reversed ? pair.0 : pair.1
                    reference.select(begin: begin, end: end, window: window, reversedTable: reversedTable)
                    current.select(begin: begin, end: end, window: window, reversedTable: reversedTable)
                    XCTAssertTrue(current.selectManager.selectedText.isEqual(to: reference.selectManager.selectedText))
                }
            }
        }
    }

    func testAttachedWindowTransitionsAndAccessibilityUseCurrentMessage() throws {
        let context = BlockContext()
        let windows = (0..<2).map { _ in Window(contentRect: NSRect(x: 0, y: 0, width: 300, height: 350), styleMask: [.borderless], backing: .buffered, defer: false) }
        windows.forEach { $0.isReleasedWhenClosed = false }
        defer { windows.forEach { $0.contentView = nil; $0.close() } }
        let native = ReusedChatTextRow(frame: NSRect(x: 0, y: 0, width: 300, height: 350))
        let current = LayerChatTextRow(frame: native.frame)
        windows[0].contentView = native; windows[1].contentView = current
        native.bind(item(1, context: context)); current.bind(item(1, context: context))
        let host = try XCTUnwrap(current.layerText)
        let transition = ContainedViewLayoutTransition.animated(duration: 0.2, curve: .easeOut)
        for revealed in [true, false] {
            let original = item(1, context: context, revealed: revealed)
            let next = item(1, context: context, revealed: revealed)
            native.bind(original, animated: true); current.bind(next, animated: true)
            transition.updateFrame(view: try XCTUnwrap(native.text), frame: native.textFrame(original))
            current.finishLayout(transition: transition)
            CATransaction.flush()
            finish()
            XCTAssertTrue(current.layerText === host)
            XCTAssertTrue(host.window === windows[1])
            XCTAssertEqual(ViewSnapshot.render(native, keepingWindow: true).differingPixels(from: ViewSnapshot.render(current, keepingWindow: true), tolerance: 0), 0)
            XCTAssertTrue(host.body.textNodes[0].onAccessibilityPress?() ?? false)
            XCTAssertEqual(next.revealedIndices, [0])
        }
    }

    func testLiveBodyAndCaptionRebindingPreserveQuoteBackgroundContents() throws {
        let context = BlockContext(), row = LayerChatTextRow(frame: NSRect(x: 0, y: 0, width: 280, height: 650))
        row.bind(item(1, context: context))
        let host = try XCTUnwrap(row.layerText)
        let background = try XCTUnwrap(host.body.textNodes[0].layer.sublayers?.compactMap { $0 as? InputTextView.FoldingTextQuoteLayer }.first)
        background.displayIfNeeded()
        XCTAssertNotNil(background.contents)
        row.bind(item(1, context: context))
        XCTAssertFalse(background.needsDisplay())
        row.bind(item(2, context: context))
        XCTAssertFalse(background.needsDisplay())
        let previousFrame = background.blockQuotes[0].frame
        let narrower = item(2, context: context)
        narrower.textLayout.measure(width: 120)
        row.bind(narrower)
        XCTAssertNotEqual(previousFrame, background.blockQuotes[0].frame)
        XCTAssertTrue(background.needsDisplay())
        background.displayIfNeeded()

        let caption = LayerCaptionRow(frame: row.frame)
        func nextCaption(_ id: Int) -> FoldingViewHarness.ChatRowItem {
            return .init([.init(messageId: id, id: UInt32(id), layout: item(id, context: context).textLayout)])
        }
        caption.bind(nextCaption(1)); caption.finishLayout()
        let captionHost = try XCTUnwrap(caption.captionViews[0].layerView)
        let captionBackground = try XCTUnwrap(captionHost.body.textNodes[0].layer.sublayers?.compactMap { $0 as? InputTextView.FoldingTextQuoteLayer }.first)
        captionBackground.displayIfNeeded()
        XCTAssertNotNil(captionBackground.contents)
        caption.bind(nextCaption(1)); caption.finishLayout()
        XCTAssertFalse(captionBackground.needsDisplay())
    }

}
