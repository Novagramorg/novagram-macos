import Cocoa
import XCTest
import TGUIKit
import InputTextView
@testable import ChatLayerEngine

final class CodeHeaderTests: XCTestCase {
    override func setUp() { TGUIKitTestBootstrap.install(); System.updateScaleFactor(2) }
    override func tearDown() { System.updateScaleFactor(2) }

    func source(_ string: String = "let value = 1\nprint(value)\nthird\nfourth\nfifth", width: CGFloat = 240, folded: Bool? = nil) -> FoldingTextLayout {
        let result = StaticQuoteTests().source(string, width: width, code: true, collapsable: folded != nil, header: true)
        if let folded { result.blocks = [result.blocks[0].measured(width: width, revealed: !folded)] }
        return result
    }

    func legacyText(_ value: NSAttributedString, range: NSRange) -> String {
        var range = range
        for index in NSMaxRange(range)..<value.length {
            if value.attribute(TextInputAttributes.quote, at: index, effectiveRange: nil) != nil { range.length += 1 }
            else { break }
        }
        return value.attributedSubstring(from: range).string
    }

    func testRunBasedCopyMatchesOriginalAcrossRangesAndUnicode() {
        var comparisons = 0
        for string in ["", "abcdefg", "a🦆é中\n"] {
            for pattern in 0..<128 {
                let value = NSMutableAttributedString(string: string)
                for index in 0..<value.length {
                    if pattern & (1 << (index % 7)) != 0 {
                        value.addAttribute(TextInputAttributes.quote, value: index % 2 == 0 ? "quote" as Any : NSNull(), range: NSRange(location: index, length: 1))
                    }
                    value.addAttribute(.foregroundColor, value: index % 2 == 0 ? NSColor.red : NSColor.blue, range: NSRange(location: index, length: 1))
                }
                for immutable in [false, true] {
                    let text = TextViewLayout(immutable ? NSAttributedString(attributedString: value) : value)
                    for start in 0...value.length {
                        for length in 0...(value.length - start) {
                            let range = NSRange(location: start, length: length)
                            XCTAssertEqual(text.blockQuoteText(startingWith: range), legacyText(value, range: range))
                            comparisons += 1
                        }
                    }
                    XCTAssertNil(text.blockQuoteText(startingWith: NSRange(location: NSNotFound, length: 0)))
                    XCTAssertNil(text.blockQuoteText(startingWith: NSRange(location: 0, length: Int.max)))
                    XCTAssertNil(text.blockQuoteText(startingWith: NSRange(location: value.length + 1, length: 0)))
                }
            }
        }
        XCTAssertEqual(comparisons, 18688)
        let mutable = NSMutableAttributedString(string: "abcd", attributes: [TextInputAttributes.quote: true])
        let layout = TextViewLayout(mutable)
        XCTAssertEqual(layout.blockQuoteText(startingWith: NSRange(location: 0, length: 1)), "abcd")
        mutable.removeAttribute(TextInputAttributes.quote, range: NSRange(location: 2, length: 1))
        XCTAssertEqual(layout.blockQuoteText(startingWith: NSRange(location: 0, length: 1)), "ab")
    }

    func testHeaderPixelsMatchNativeAtAllScalesAndFoldStates() throws {
        var comparisons = 0
        for scale in [CGFloat(1), 2, 3] {
            System.updateScaleFactor(scale)
            for width in [CGFloat(190), 420] {
                for folded in [nil, false, true] as [Bool?] {
                    for selected in [false, true] {
                        let layout = source("let value = \"🦆\"\nprint(value)\nمرحبا 中文\nfourth\nfifth", width: width, folded: folded)
                        if selected { layout.blocks[0].text.selectedRange.range = NSRange(location: 1, length: 12) }
                        let scene = ChatLayerSceneView(frame: NSRect(origin: .zero, size: layout.size))
                        scene.backgroundColor = .clear
                        let body = ChatLayerMessageTextNode(id: "body")
                        body.revealBlockAtIndex = { _ in }
                        XCTAssertTrue(try body.update(ChatLayerMessageTextPresentation(layout), messageId: 1, selectable: true))
                        try scene.root.setChildren([body])
                        let native = makeReferenceFoldingWrapper(layout.blocks[0])
                        XCTAssertEqual(ViewSnapshot.render(native, scale: scale).differingPixels(from: ViewSnapshot.render(scene, scale: scale), tolerance: 0), 0, "scale=\(scale), width=\(width), folded=\(String(describing: folded)), selected=\(selected)")
                        XCTAssertEqual(viewTreeCount(scene), 1)
                        XCTAssertEqual(body.textNodes[0].children.count, 1)
                        comparisons += 1
                    }
                }
            }
        }
        XCTAssertEqual(comparisons, 36)
    }

    func testHeaderCopyCancellationReuseAndFoldingDoNotInterfere() throws {
        for folded in [nil, false, true] as [Bool?] {
            let layout = source(folded: folded)
            let linked = NSMutableAttributedString(attributedString: layout.blocks[0].text.attributedString)
            linked.addAttribute(.link, value: "https://example.org", range: NSRange(location: 0, length: 3))
            layout.blocks = [FoldingTextLayout.ViewLayout(text: TextViewLayout(linked)).measured(width: 240, revealed: folded != true)]
            var copied: [String] = [], toggles = 0, links = 0
            layout.blocks[0].text.interactions.copyToClipboard = { copied.append($0) }
            layout.blocks[0].text.interactions.processURL = { _ in links += 1 }
            let body = ChatLayerMessageTextNode(id: "body")
            body.revealBlockAtIndex = { _ in toggles += 1 }
            let scene = ChatLayerSceneView(frame: NSRect(x: 0, y: 0, width: 400, height: 400))
            try body.update(ChatLayerMessageTextPresentation(layout), messageId: 1, selectable: true)
            try scene.root.setChildren([body])
            scene.layout()
            let node = body.textNodes[0]
            let header = try XCTUnwrap(node.children.first as? ChatLayerButtonNode)
            let point = NSPoint(x: header.frame.midX, y: header.frame.midY)
            func click() {
                XCTAssertTrue(scene.handlePointer(.down, at: point))
                XCTAssertTrue(scene.handlePointer(.up, at: point))
            }
            click()
            XCTAssertEqual(copied, [layout.blocks[0].text.attributedString.string])
            XCTAssertEqual(toggles, 0)
            XCTAssertEqual(links, 0)
            let link = try XCTUnwrap(layout.blocks[0].text.rects(NSRange(location: 0, length: 3)).first?.0)
            let linkPoint = NSPoint(x: link.midX, y: link.midY)
            scene.handlePointer(.down, at: linkPoint)
            scene.handlePointer(.up, at: linkPoint)
            XCTAssertEqual(links, 1)
            XCTAssertEqual(toggles, 0)
            XCTAssertEqual(copied.count, 1)
            node.setSelection(NSRange(location: 0, length: 3))
            click()
            XCTAssertEqual(copied.count, 2)
            scene.handlePointer(.down, at: point)
            scene.handlePointer(.dragged, at: NSPoint(x: 390, y: 390))
            scene.handlePointer(.up, at: NSPoint(x: 390, y: 390))
            XCTAssertEqual(copied.count, 2)
            scene.handlePointer(.down, at: point)
            scene.cancelInput()
            scene.handlePointer(.up, at: point)
            XCTAssertEqual(copied.count, 2)
            scene.handlePointer(.down, at: point)
            try body.update(ChatLayerMessageTextPresentation(layout), messageId: 2, selectable: true)
            scene.handlePointer(.up, at: point)
            XCTAssertEqual(copied.count, 2)
            XCTAssertTrue(node.children[0] === header)
            try body.update(ChatLayerMessageTextPresentation(layout), messageId: 2, selectable: false)
            click()
            XCTAssertEqual(copied.count, 3)
            node.isEnabled = false
            click()
            XCTAssertEqual(copied.count, 3)
            node.isEnabled = true
            try body.update(ChatLayerMessageTextPresentation(MessageTextTests().layout(["plain"])), messageId: 3, selectable: true)
            XCTAssertTrue(node.children.isEmpty)
            XCTAssertNil(header.scene)
            XCTAssertNil(header.parent)
        }
    }

    func testMultipleHeadersCopyTheirOwnBlocksAndReuseUpdatedRanges() throws {
        let first = "let first = 1\nprint(first)"
        let second = "let second = 2\nprint(second)"
        let string = first + "\nplain separator\n" + second
        let value = NSMutableAttributedString(string: string, attributes: [.font: NSFont.systemFont(ofSize: 14)])
        let title = TextNode.layoutText(NSAttributedString(string: "Swift", attributes: [.font: NSFont.systemFont(ofSize: 12)]), nil, 1, .end, NSSize(width: 200, height: 40), nil, false, .left)
        for (index, block) in [first, second].enumerated() {
            value.addAttribute(TextInputAttributes.quote, value: TextViewBlockQuoteData(id: index, colors: .init(main: .blue), isCode: true, header: title), range: (string as NSString).range(of: block))
        }
        let text = TextViewLayout(value)
        text.measure(width: 240)
        let layout = FoldingTextLayout(blocks: [.init(text: text)])
        var copied: [String] = []
        text.interactions.copyToClipboard = { copied.append($0) }
        let scene = ChatLayerSceneView(frame: NSRect(x: 0, y: 0, width: 400, height: 400))
        let body = ChatLayerMessageTextNode(id: "body")
        try body.update(ChatLayerMessageTextPresentation(layout), messageId: 1, selectable: true)
        try scene.root.setChildren([body])
        scene.layout()
        let node = body.textNodes[0]
        XCTAssertEqual(node.children.count, 2)
        for header in node.children {
            let point = NSPoint(x: header.frame.midX, y: header.frame.midY)
            XCTAssertTrue(scene.handlePointer(.down, at: point))
            XCTAssertTrue(scene.handlePointer(.up, at: point))
        }
        XCTAssertEqual(copied, [first, second])
        let replacement = source("replacement")
        replacement.blocks[0].text.interactions.copyToClipboard = { copied.append($0) }
        let removed = node.children[1]
        try body.update(ChatLayerMessageTextPresentation(replacement), messageId: 2, selectable: true)
        XCTAssertEqual(node.children.count, 1)
        XCTAssertNil(removed.scene)
        XCTAssertTrue(node.children[0].onAccessibilityPress?() == true)
        XCTAssertEqual(copied.last, "replacement")
    }

    func testHeaderKeyboardAccessibilityAndResizing() throws {
        TGUIKitAccessibility.isEnabled = true
        let layout = source()
        var copied = 0
        layout.blocks[0].text.interactions.copyToClipboard = { _ in copied += 1 }
        let scene = ChatLayerSceneView(frame: NSRect(x: 0, y: 0, width: 400, height: 400))
        let body = ChatLayerMessageTextNode(id: "body")
        try body.update(ChatLayerMessageTextPresentation(layout), messageId: 1, selectable: false)
        try scene.root.setChildren([body])
        let node = body.textNodes[0]
        let header = try XCTUnwrap(node.children.first)
        XCTAssertTrue(header.acceptsKeyboardFocus)
        let textElement = try XCTUnwrap(scene.accessibilityChildren()?.first as? NSAccessibilityProtocol)
        let element = try XCTUnwrap(textElement.accessibilityChildren()?.first as? NSAccessibilityProtocol)
        XCTAssertEqual(element.accessibilityRole(), .button)
        XCTAssertTrue(element.accessibilityPerformPress())
        header.isEnabled = false
        XCTAssertFalse(element.accessibilityPerformPress())
        header.isEnabled = true
        for code in [UInt16(36), 49] {
            let event = try XCTUnwrap(NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0, windowNumber: 0, context: nil, characters: "", charactersIgnoringModifiers: "", isARepeat: false, keyCode: code))
            XCTAssertTrue(header.onKeyDown?(event) == true)
        }
        XCTAssertEqual(copied, 3)
        let width = header.frame.width
        layout.blocks[0].text.measure(width: 80)
        try body.update(ChatLayerMessageTextPresentation(layout), messageId: 1, selectable: false)
        XCTAssertTrue(node.children[0] === header)
        XCTAssertLessThan(header.frame.width, width)
        XCTAssertEqual(header.frame.width, layout.blocks[0].text.blockQuotes[0].frame.width)
    }
}
