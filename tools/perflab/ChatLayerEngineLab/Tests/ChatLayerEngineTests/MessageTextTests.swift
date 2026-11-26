import Cocoa
import XCTest
import TGUIKit
import InputTextView
@testable import ChatLayerEngine

final class MessageTextTests: XCTestCase {
    override func setUp() { TGUIKitTestBootstrap.install(); System.updateScaleFactor(2) }
    override func tearDown() { System.updateScaleFactor(2) }

    func layout(_ strings: [String], width: CGFloat = 240) -> FoldingTextLayout {
        return FoldingTextLayout(blocks: strings.map {
            let text = TextViewLayout(NSAttributedString(string: $0, attributes: [.font: NSFont.systemFont(ofSize: 14), .foregroundColor: NSColor.black]))
            text.measure(width: width)
            return .init(text: text)
        })
    }

    func testBlockGeometryAndPixelsMatchNativeTextViews() throws {
        var comparisons = 0
        for scale in [CGFloat(1), 2, 3] {
            System.updateScaleFactor(scale)
            for width in [CGFloat(180), 400] {
                for strings in [["One paragraph", "Another longer paragraph wrapping onto multiple lines at small widths."], ["مرحبا English שלום", "中文 日本語 한글\ncafé 👩🏽‍💻 🦆"]] {
                    try autoreleasepool {
                        let source = layout(strings, width: width)
                        let presentation = ChatLayerMessageTextPresentation(ChatMessageItem(textLayout: source))
                        XCTAssertTrue(presentation.nativeFeatures.isEmpty)
                        let size = NSSize(width: width + 40, height: source.size.height + 40)
                        let native = View(frame: NSRect(origin: .zero, size: size))
                        native.backgroundColor = .clear
                        var y: CGFloat = 20
                        for block in source.blocks {
                            let text = TextView()
                            text.disableBackgroundDrawing = true
                            text.update(block.text)
                            text.frame.origin = NSPoint(x: 20, y: y)
                            native.addSubview(text)
                            y += text.frame.height
                        }
                        let scene = ChatLayerSceneView(frame: native.frame)
                        scene.backgroundColor = .clear
                        let body = ChatLayerMessageTextNode(id: "body")
                        XCTAssertTrue(try body.update(presentation, messageId: 1, selectable: true))
                        body.frame.origin = NSPoint(x: 20, y: 20)
                        try scene.root.setChildren([body])
                        XCTAssertEqual(body.frame.size, source.size)
                        XCTAssertEqual(body.textNodes.count, source.blocks.count)
                        XCTAssertEqual(viewTreeCount(scene), 1)
                        for (node, view) in zip(body.textNodes, native.subviews) {
                            XCTAssertEqual(node.frame.offsetBy(dx: 20, dy: 20), view.frame)
                        }
                        let old = ViewSnapshot.render(native, scale: scale)
                        let new = ViewSnapshot.render(scene, scale: scale)
                        XCTAssertEqual(old.differingPixels(from: new, tolerance: 0), 0)
                        comparisons += 1
                    }
                }
            }
        }
        XCTAssertEqual(comparisons, 12)
    }

    func testRebindingRetainsNodesAndSelectionUntilMessageChanges() throws {
        let body = ChatLayerMessageTextNode(id: "body")
        let source = layout(["first", "second"])
        let presentation = ChatLayerMessageTextPresentation(source)
        try body.update(presentation, messageId: 1, selectable: true)
        let first = body.textNodes[0], second = body.textNodes[1]
        first.setExternalSelection(NSRange(location: 0, length: 3))
        try body.update(presentation, messageId: 1, selectable: true)
        XCTAssertTrue(body.textNodes[0] === first)
        XCTAssertTrue(body.textNodes[1] === second)
        XCTAssertEqual(first.textLayout?.selectedRange.range, NSRange(location: 0, length: 3))
        try body.update(presentation, messageId: 2, selectable: true)
        XCTAssertTrue(body.textNodes[0] === first)
        XCTAssertEqual(first.textLayout?.selectedRange.range.location, NSNotFound)
        first.setSelection(NSRange(location: 1, length: 2))
        try body.update(presentation, messageId: 2, selectable: false)
        XCTAssertEqual(first.textLayout?.selectedRange.range.location, NSNotFound)
        XCTAssertTrue(body.selectableTextNodeIds.isEmpty)
    }

    func testShrinkingAndFallbackRemoveStaleTextAndSelection() throws {
        let scene = ChatLayerSceneView(frame: NSRect(x: 0, y: 0, width: 300, height: 200))
        let body = ChatLayerMessageTextNode(id: "body")
        try scene.root.setChildren([body])
        try body.update(ChatLayerMessageTextPresentation(layout(["first", "second"])), messageId: 1, selectable: true)
        let removed = body.textNodes[1]
        removed.setExternalSelection(NSRange(location: 0, length: 3))
        try body.update(ChatLayerMessageTextPresentation(layout(["replacement"])), messageId: 1, selectable: true)
        XCTAssertNil(removed.parent)
        XCTAssertNil(removed.scene)
        XCTAssertEqual(removed.textLayout?.selectedRange.range.location, NSNotFound)
        let remaining = body.textNodes[0]
        let unsupported = ChatLayerMessageTextPresentation(blocks: [], size: NSSize(width: 200, height: 100), nativeFeatures: [.quote], requiresRevealAction: false)
        XCTAssertFalse(try body.update(unsupported, messageId: 1, selectable: true))
        XCTAssertTrue(body.children.isEmpty)
        XCTAssertTrue(body.textNodes.isEmpty)
        XCTAssertEqual(body.frame.size, .zero)
        XCTAssertNil(remaining.scene)
    }

    func testRichFeaturesRequireNativeRendering() {
        for (attribute, feature) in [(TextInputAttributes.spoiler, ChatLayerMessageTextPresentation.NativeFeature.spoiler), (TextInputAttributes.customEmoji, .embeddedItem), (TextInputAttributes.formattedDate, .formattedDate)] {
            let text = TextViewLayout(NSAttributedString(string: "rich", attributes: [.font: NSFont.systemFont(ofSize: 14), attribute: true]))
            text.measure(width: 200)
            let source = FoldingTextLayout(blocks: [.init(text: text)])
            XCTAssertTrue(ChatLayerMessageTextPresentation(source).nativeFeatures.contains(feature))
        }
        let quote = TextViewBlockQuoteData(id: 1, colors: .init(main: .blue), collapsable: true)
        let quotedText = TextViewLayout(NSAttributedString(string: "quoted text\nsecond line\nthird line\nfourth line", attributes: [.font: NSFont.systemFont(ofSize: 14), TextInputAttributes.quote: quote]))
        quotedText.measure(width: 200)
        XCTAssertNotNil(ChatLayerMessageTextPresentation(FoldingTextLayout(blocks: [.init(text: quotedText)])).blocks[0].folding)
        let source = layout(["streaming"])
        let streaming = FoldingTextLayout(blocks: source.blocks, appendingAnimation: true)
        XCTAssertTrue(ChatLayerMessageTextPresentation(streaming).nativeFeatures.contains(.streaming))
        let collapsed = FoldingTextLayout(blocks: [.init(text: source.blocks[0].text, isRevealed: false, size: NSSize(width: 100, height: 5))])
        let result = ChatLayerMessageTextPresentation(collapsed)
        XCTAssertTrue(result.nativeFeatures.contains(.collapsed))
        XCTAssertEqual(result.blocks[0].frame.height, 5)
        let background = layout(["block background"])
        background.blocks[0].text.generateAutoBlock(backgroundColor: .blue)
        XCTAssertTrue(ChatLayerMessageTextPresentation(background).nativeFeatures.contains(.blockBackground))
    }

    func testSelectionRegistrationUsesNestedBlockCoordinates() throws {
        let scene = ChatLayerSceneView(frame: NSRect(x: 0, y: 0, width: 300, height: 200))
        scene.layout()
        let body = ChatLayerMessageTextNode(id: "body")
        try body.update(ChatLayerMessageTextPresentation(layout(["first", "second"])), messageId: 1, selectable: true)
        body.frame.origin = NSPoint(x: 20, y: 30)
        try scene.root.setChildren([body])
        scene.selectableTextNodeIds = body.selectableTextNodeIds
        let fragments = scene.applyBubbleSelection(begin: .zero, end: NSPoint(x: 300, y: 200), isStartRow: false, isEndRow: false, reversed: false)
        XCTAssertEqual(fragments.count, 1)
        XCTAssertEqual(fragments[0].attributedString.attributedSubstring(from: fragments[0].range).string, "first\nsecond")
        scene.clearBubbleSelection()
        XCTAssertTrue(body.textNodes.allSatisfy { $0.textLayout?.selectedRange.range.location == NSNotFound })
    }

    func testRemovedBlocksAreReleasedAcrossGrowthAndEmptyUpdates() throws {
        let body = ChatLayerMessageTextNode(id: "body")
        for count in [1, 8, 2, 16, 0, 4] {
            let source = layout((0..<count).map { "paragraph \($0)" })
            try body.update(ChatLayerMessageTextPresentation(source), messageId: count, selectable: true)
            XCTAssertEqual(body.textNodes.count, count)
            XCTAssertEqual(Set(body.textNodes.map(\.id)).count, count)
        }
        weak var removed = body.textNodes.last
        try body.update(ChatLayerMessageTextPresentation(layout([])), messageId: 0, selectable: true)
        XCTAssertNil(removed)
        XCTAssertEqual(body.frame.size, .zero)
    }

    func testRemeasuringTheSameLayoutUpdatesFramesAndDrawingBounds() throws {
        let body = ChatLayerMessageTextNode(id: "body")
        let source = layout(["A long enough paragraph that wraps after the available width changes."])
        try body.update(ChatLayerMessageTextPresentation(source), messageId: 1, selectable: true)
        let node = body.textNodes[0]
        let initialHeight = node.frame.height
        source.blocks[0].text.measure(width: 80)
        try body.update(ChatLayerMessageTextPresentation(source), messageId: 1, selectable: true)
        XCTAssertTrue(body.textNodes[0] === node)
        XCTAssertGreaterThan(node.frame.height, initialHeight)
        XCTAssertEqual(body.frame.size, source.size)
        XCTAssertEqual(node.drawingLayer.bounds, node.layer.bounds.insetBy(dx: -2, dy: -3))
        let drawingBounds = node.drawingLayer.bounds
        node.frame.origin = NSPoint(x: 13, y: 27)
        XCTAssertEqual(node.drawingLayer.bounds, drawingBounds)
        XCTAssertEqual(node.frame.origin, NSPoint(x: 13, y: 27))
    }

    func testPreparedLinkMetadataPreservesActivationOnNonselectableText() throws {
        let value = NSMutableAttributedString(string: "open", attributes: [.font: NSFont.systemFont(ofSize: 14), .link: "target"])
        let text = TextViewLayout(value)
        text.measure(width: 200)
        var activated = 0
        text.interactions.processURL = { _ in activated += 1 }
        let source = FoldingTextLayout(blocks: [.init(text: text)])
        let presentation = ChatLayerMessageTextPresentation(source)
        XCTAssertTrue(presentation.blocks[0].hasLinks)
        let scene = ChatLayerSceneView(frame: NSRect(x: 0, y: 0, width: 300, height: 100))
        scene.layout()
        let body = ChatLayerMessageTextNode(id: "body")
        try body.update(presentation, messageId: 1, selectable: false)
        try scene.root.setChildren([body])
        XCTAssertTrue(body.textNodes[0].acceptsPointerEvents)
        XCTAssertTrue(scene.handlePointer(.down, at: NSPoint(x: 3, y: 6)))
        XCTAssertTrue(scene.handlePointer(.up, at: NSPoint(x: 3, y: 6)))
        XCTAssertEqual(activated, 1)
        XCTAssertTrue(scene.handlePointer(.down, at: NSPoint(x: 3, y: 6)))
        try body.update(presentation, messageId: 2, selectable: false)
        _ = scene.handlePointer(.up, at: NSPoint(x: 3, y: 6))
        XCTAssertEqual(activated, 1)
        try body.update(ChatLayerMessageTextPresentation(layout(["plain"])), messageId: 2, selectable: false)
        XCTAssertFalse(body.textNodes[0].acceptsPointerEvents)
        XCTAssertNil(scene.hitNode(at: NSPoint(x: 3, y: 6)))
    }
}
