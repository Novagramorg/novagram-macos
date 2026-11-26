import Cocoa
import XCTest
import TGUIKit
import InputTextView
@testable import ChatLayerEngine

final class HighlightTests: XCTestCase {
    override func setUp() { TGUIKitTestBootstrap.install(); System.updateScaleFactor(2) }
    override func tearDown() { System.updateScaleFactor(2) }

    private func highlightedLayer(_ node: ChatLayerTextNode) -> CALayer? {
        node.layer.sublayers?.first(where: { $0 !== node.drawingLayer && $0.opacity == 0.5 })
    }

    private func textViews(_ view: NSView) -> [TextView] {
        if let text = view as? TextView { return [text] }
        return view.subviews.flatMap(textViews)
    }

    private func compare(_ source: FoldingTextLayout, text: String, range: NSRange?, scale: CGFloat, quote: Bool = false) throws {
        let frame = NSRect(x: 0, y: 0, width: source.size.width + 40, height: source.size.height + 40)
        let native = View(frame: frame)
        native.backgroundColor = .clear
        var views: [TextView] = []
        var y: CGFloat = 20
        for block in source.blocks {
            if quote {
                let wrapper = makeCandidateFoldingWrapper(block)
                wrapper.frame.origin = NSPoint(x: 20, y: y)
                native.addSubview(wrapper)
                views += textViews(wrapper)
            } else {
                let view = TextView()
                view.disableBackgroundDrawing = true
                view.update(block.text)
                view.frame.origin = NSPoint(x: 20, y: y)
                native.addSubview(view)
                views.append(view)
            }
            y += block.isRevealed ? block.layoutSize.height : block.size.height
        }
        XCTAssertEqual(views.count, source.blocks.count)
        let scene = ChatLayerSceneView(frame: frame)
        scene.backgroundColor = .clear
        let body = ChatLayerMessageTextNode(id: "message")
        body.revealBlockAtIndex = { _ in }
        try body.update(ChatLayerMessageTextPresentation(source), messageId: 1, selectable: true)
        body.frame.origin = NSPoint(x: 20, y: 20)
        try scene.root.setChildren([body])
        let baseline = ViewSnapshot.render(native, scale: scale)
        NativeMessageHighlightHarness(layouts: source, textViews: views).highlight(text: text, color: .yellow, range: range)
        body.highlight(text: text, color: .yellow, range: range, in: source)
        let expected = ViewSnapshot.render(native, scale: scale)
        let actual = ViewSnapshot.render(scene, scale: scale)
        let differences = expected.differingPixels(from: actual, tolerance: 0)
        if differences != 0 {
            try expected.write(to: URL(fileURLWithPath: "/tmp/chat-highlight-native.png"))
            try actual.write(to: URL(fileURLWithPath: "/tmp/chat-highlight-layer.png"))
        }
        if quote, scale == 2, text == "First" {
            try expected.write(to: URL(fileURLWithPath: "/tmp/chat-highlight-final-native.png"))
            try actual.write(to: URL(fileURLWithPath: "/tmp/chat-highlight-final-layer.png"))
        }
        XCTAssertEqual(differences, 0, "\(text), \(String(describing: range)), \(scale), quote=\(quote)")
        if body.textNodes.contains(where: { highlightedLayer($0) != nil }) {
            XCTAssertGreaterThan(expected.differingPixels(from: baseline, tolerance: 0), 0)
        }
        XCTAssertEqual(viewTreeCount(scene), 1)
    }

    func testPlainHighlightPixelsMatchNativeAcrossRangesAndLanguages() throws {
        var pairs = 0
        for scale in [CGFloat(1), 2, 3] {
            System.updateScaleFactor(scale)
            for (string, text) in [("word then word", "word"), ("مرحبا English שלום", "مرحبا"), ("中文 日本語 café 👩🏽‍💻", "👩🏽‍💻")] {
                let source = MessageTextTests().layout([string], width: 160)
                let last = (string as NSString).range(of: text, options: .backwards)
                for range in [nil, last, NSRange(location: Int.max, length: Int.max), NSRange(location: -1, length: 2), NSRange(location: 0, length: Int.max), NSRange(location: 1, length: -1)] {
                    try compare(source, text: text, range: range, scale: scale)
                    pairs += 1
                }
            }
        }
        XCTAssertEqual(pairs, 54)
    }

    func testGlobalRangesMapToTheCorrectBlocks() throws {
        var pairs = 0
        for scale in [CGFloat(1), 2, 3] {
            System.updateScaleFactor(scale)
            let source = MessageTextTests().layout(["first word\n", "second word\n", "last 👩🏽‍💻 word"], width: 170)
            let string = source.attributedString.string as NSString
            for text in ["word", "word\nsecond", "👩🏽‍💻 word", "missing"] {
                let range = string.range(of: text, options: .backwards)
                try compare(source, text: text, range: range, scale: scale)
                pairs += 1
            }
        }
        XCTAssertEqual(pairs, 12)
    }

    func testQuoteHighlightPixelsMatchNativeIncludingCollapsedFade() throws {
        var pairs = 0
        let string = "First quoted line\nSecond quoted line\nThird quoted line with long words\nFourth quoted line\nLast quoted line"
        for scale in [CGFloat(1), 2, 3] {
            System.updateScaleFactor(scale)
            for code in [false, true] {
                for revealed in [false, true] {
                    let source = FoldingQuoteTests().source(string, width: 200, revealed: revealed, code: code)
                    for text in ["First", "Third quoted line with long words"] {
                        try compare(source, text: text, range: (string as NSString).range(of: text), scale: scale, quote: true)
                        pairs += 1
                    }
                }
            }
            for code in [false, true] {
                let source = StaticQuoteTests().source(string, width: 200, code: code, colors: 2)
                try compare(source, text: "Second", range: nil, scale: scale, quote: true)
                pairs += 1
            }
        }
        XCTAssertEqual(pairs, 30)
    }

    func testBlockRangesWithSeparatorsMatchNative() throws {
        let blocks = MessageTextTests().layout(["first", "second"]).blocks
        let source = FoldingTextLayout(blocks: blocks, attributedString: NSAttributedString(string: "first\nsecond"), blockRanges: [NSRange(location: 0, length: 5), NSRange(location: 6, length: 6)])
        try compare(source, text: "first\nsecond", range: NSRange(location: 0, length: 12), scale: 2)
    }

    func testHighlightDoesNotChangeSelectionOrAddInteractiveNodes() throws {
        let source = MessageTextTests().layout(["Select this word"])
        let body = ChatLayerMessageTextNode(id: "body")
        let scene = ChatLayerSceneView(frame: NSRect(x: 0, y: 0, width: 300, height: 100))
        try scene.root.setChildren([body])
        try body.update(ChatLayerMessageTextPresentation(source), messageId: 1, selectable: true)
        let node = body.textNodes[0]
        XCTAssertEqual(node.layer.sublayers?.count, 1)
        node.setSelection(NSRange(location: 0, length: 6))
        var changes = 0
        node.onSelectionChanged = { _ in changes += 1 }
        body.highlight(text: "word", color: .yellow, in: source)
        XCTAssertNotNil(highlightedLayer(node))
        XCTAssertEqual(node.textLayout?.selectedRange.range, NSRange(location: 0, length: 6))
        XCTAssertEqual(changes, 0)
        XCTAssertEqual(body.children.count, 1)
        XCTAssertTrue(node.children.isEmpty)
        XCTAssertTrue(node.acceptsPointerEvents)
    }

    func testReplacingClearingAndRebindingReleaseOldHighlights() throws {
        let source = MessageTextTests().layout(["first second"])
        let scene = ChatLayerSceneView(frame: NSRect(x: 0, y: 0, width: 300, height: 100))
        let body = ChatLayerMessageTextNode(id: "body")
        try scene.root.setChildren([body])
        try body.update(ChatLayerMessageTextPresentation(source), messageId: 1, selectable: true)
        let node = body.textNodes[0]
        body.highlight(text: "first", color: .yellow, in: source)
        let old = try XCTUnwrap(highlightedLayer(node))
        body.highlight(text: "second", color: .red, in: source)
        XCTAssertNil(old.superlayer)
        XCTAssertNotNil(highlightedLayer(node))
        body.highlight(text: "missing", color: .red, in: source)
        XCTAssertNil(highlightedLayer(node))
        body.highlight(text: "first", color: .yellow, in: source)
        try body.update(ChatLayerMessageTextPresentation(source), messageId: 2, selectable: true)
        XCTAssertNil(highlightedLayer(node))
        body.highlight(text: "first", color: .yellow, in: source)
        let wrong = MessageTextTests().layout(["first second"])
        body.highlight(text: "second", color: .red, in: wrong)
        XCTAssertNotNil(highlightedLayer(node))
        try scene.root.setChildren([])
        XCTAssertNil(highlightedLayer(node))
    }

    func testMutableTextAndGeometryChangesInvalidateStaleHighlight() throws {
        let source = MessageTextTests().layout(["A sufficiently long sentence for narrow width"])
        let node = ChatLayerTextNode(id: "node", selectable: true)
        node.update(source.blocks[0].text)
        node.highlight(text: "sentence", color: .yellow)
        XCTAssertNotNil(highlightedLayer(node))
        source.blocks[0].text.measure(width: 70)
        node.update(source.blocks[0].text)
        XCTAssertNil(highlightedLayer(node))
        node.highlight(text: "sentence", color: .yellow)
        source.blocks[0].text.setAttributedString(NSAttributedString(string: "Replacement", attributes: [.font: NSFont.systemFont(ofSize: 14)]))
        source.blocks[0].text.measure(width: 70)
        node.update(source.blocks[0].text)
        XCTAssertNil(highlightedLayer(node))
    }

    func testExpiredOlderRequestCannotRemoveNewerHighlight() throws {
        let source = MessageTextTests().layout(["first second"])
        let node = ChatLayerTextNode(id: "node", selectable: true)
        node.update(source.blocks[0].text)
        node.highlight(text: "first", color: .yellow)
        let replaced = expectation(description: "replace")
        let olderExpired = expectation(description: "old timeout")
        let newerExpired = expectation(description: "new timeout")
        var newer: CALayer?
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
            node.highlight(text: "second", color: .yellow)
            newer = self.highlightedLayer(node)
            replaced.fulfill()
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 3.2) {
            XCTAssertTrue(self.highlightedLayer(node) === newer)
            XCTAssertNotNil(newer?.superlayer)
            olderExpired.fulfill()
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 3.9) {
            CATransaction.flush()
            XCTAssertTrue(newer?.superlayer == nil || newer?.animation(forKey: "opacity") != nil)
            newerExpired.fulfill()
        }
        wait(for: [replaced, olderExpired, newerExpired], timeout: 6)
    }

    func testPendingHighlightDoesNotRetainNode() {
        weak var weakNode: ChatLayerTextNode?
        weak var weakLayer: CALayer?
        autoreleasepool {
            let node = ChatLayerTextNode(id: "node", selectable: true)
            node.update(MessageTextTests().layout(["word"]).blocks[0].text)
            node.highlight(text: "word", color: .yellow)
            weakNode = node
            weakLayer = highlightedLayer(node)
        }
        CATransaction.flush()
        XCTAssertNil(weakNode)
        XCTAssertNil(weakLayer)
    }
}
