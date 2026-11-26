import Cocoa
import XCTest
import TGUIKit
import InputTextView
@testable import ChatLayerEngine

final class FoldingQuoteTests: XCTestCase {
    override func setUp() { TGUIKitTestBootstrap.install(); System.updateScaleFactor(2) }
    override func tearDown() { System.updateScaleFactor(2) }

    func source(_ string: String, width: CGFloat = 240, revealed: Bool, code: Bool = false, colors: Int = 0) -> FoldingTextLayout {
        let layout = StaticQuoteTests().source(string, width: width, code: code, colors: colors, collapsable: true)
        layout.blocks = [layout.blocks[0].measured(width: width, revealed: revealed)]
        return layout
    }

    func testFoldedAndExpandedPixelsMatchCapturedNativeWrapper() throws {
        let strings = ["First quoted line\nSecond quoted line\nThird quoted line\nFourth quoted line\nLast quoted line", "مرحبا بالعالم English שלום\nالعربية\nمرحبا\nשלום\nAnother quoted line", "中文 日本語 한글\ncafé 👩🏽‍💻 🦆\nCombining accents café\n中文\nLast quoted line"]
        var comparisons = 0
        for scale in [CGFloat(1), 2, 3] {
            System.updateScaleFactor(scale)
            for width in [CGFloat(190), 420] {
                for (variant, string) in strings.enumerated() {
                    for code in [false, true] {
                        for revealed in [false, true] {
                            try autoreleasepool {
                                let layout = source(string, width: width, revealed: revealed, code: code, colors: variant)
                                let presentation = ChatLayerMessageTextPresentation(layout)
                                XCTAssertTrue(presentation.nativeFeatures.isEmpty)
                                XCTAssertNotNil(presentation.blocks[0].folding)
                                let frame = NSRect(x: 0, y: 0, width: width + 40, height: layout.size.height + 40)
                                func canvas(_ wrapper: View) -> View {
                                    let view = View(frame: frame)
                                    view.backgroundColor = .clear
                                    wrapper.frame.origin = NSPoint(x: 20, y: 20)
                                    view.addSubview(wrapper)
                                    return view
                                }
                                let native = canvas(makeReferenceFoldingWrapper(layout.blocks[0]))
                                let migrated = canvas(makeCandidateFoldingWrapper(layout.blocks[0]))
                                let scene = ChatLayerSceneView(frame: frame)
                                scene.backgroundColor = .clear
                                let body = ChatLayerMessageTextNode(id: "body")
                                body.revealBlockAtIndex = { _ in }
                                XCTAssertTrue(try body.update(presentation, messageId: 1, selectable: true))
                                body.frame.origin = NSPoint(x: 20, y: 20)
                                try scene.root.setChildren([body])
                                let expected = ViewSnapshot.render(native, scale: scale)
                                XCTAssertEqual(expected.differingPixels(from: ViewSnapshot.render(migrated, scale: scale), tolerance: 0), 0)
                                let after = ViewSnapshot.render(scene, scale: scale)
                                let differences = expected.differingPixels(from: after, tolerance: 0)
                                if differences != 0 {
                                    let base = URL(fileURLWithPath: "/tmp/chat-fold-\(scale)-\(width)-\(variant)-\(code)-\(revealed)")
                                    try expected.write(to: base.appendingPathExtension("native.png"))
                                    try after.write(to: base.appendingPathExtension("layers.png"))
                                }
                                XCTAssertEqual(differences, 0, "scale=\(scale) width=\(width) variant=\(variant) code=\(code) revealed=\(revealed)")
                                XCTAssertEqual(viewTreeCount(scene), 1)
                                comparisons += 1
                            }
                        }
                    }
                }
            }
        }
        XCTAssertEqual(comparisons, 72)
    }
    func testToggleLinksSelectionAndCancelledPresses() throws {
        let layout = source("Quoted text to select\nSecond line\nThird line\nFourth line\nLast line", revealed: false)
        let value = NSMutableAttributedString(attributedString: layout.blocks[0].text.attributedString)
        value.addAttribute(.link, value: "https://example.org", range: NSRange(location: 0, length: 6))
        layout.blocks = [FoldingTextLayout.ViewLayout(text: TextViewLayout(value)).measured(width: 240, revealed: false)]
        let scene = ChatLayerSceneView(frame: NSRect(x: 0, y: 0, width: 300, height: 300))
        let body = ChatLayerMessageTextNode(id: "body")
        var toggles: [Int] = [], links = 0
        body.revealBlockAtIndex = { toggles.append($0) }
        layout.blocks[0].text.interactions.processURL = { _ in links += 1 }
        try body.update(ChatLayerMessageTextPresentation(layout), messageId: 1, selectable: true)
        try scene.root.setChildren([body])
        scene.layout()
        let node = body.textNodes[0]
        let arrow = NSPoint(x: node.frame.width - 8, y: node.frame.height - 9)
        func click(_ point: NSPoint) {
            XCTAssertTrue(scene.handlePointer(.down, at: point))
            XCTAssertTrue(scene.handlePointer(.up, at: point))
        }
        click(arrow)
        XCTAssertEqual(toggles, [0])
        let linkRect = try XCTUnwrap(layout.blocks[0].text.rects(NSRange(location: 0, length: 6)).first?.0)
        click(NSPoint(x: linkRect.midX, y: linkRect.midY))
        XCTAssertEqual(links, 1)
        XCTAssertEqual(toggles, [0])
        node.setSelection(NSRange(location: 1, length: 4))
        click(arrow)
        XCTAssertEqual(toggles, [0])
        XCTAssertFalse(layout.blocks[0].text.selectedRange.hasSelectText)
        click(arrow)
        XCTAssertEqual(toggles, [0, 0])
        scene.handlePointer(.down, at: NSPoint(x: 12, y: 12))
        scene.handlePointer(.dragged, at: NSPoint(x: 80, y: 12))
        scene.handlePointer(.up, at: NSPoint(x: 80, y: 12))
        XCTAssertTrue(layout.blocks[0].text.selectedRange.hasSelectText)
        XCTAssertEqual(toggles.count, 2)
        node.resetInteraction()
        scene.handlePointer(.down, at: arrow)
        scene.cancelInput()
        scene.handlePointer(.up, at: arrow)
        XCTAssertEqual(toggles.count, 2)
        scene.handlePointer(.down, at: arrow)
        try body.update(ChatLayerMessageTextPresentation(layout), messageId: 2, selectable: true)
        scene.handlePointer(.up, at: arrow)
        XCTAssertEqual(toggles.count, 2)
        node.isEnabled = false
        click(arrow)
        XCTAssertEqual(toggles.count, 2)
        node.isEnabled = true
        try body.update(ChatLayerMessageTextPresentation(layout), messageId: 2, selectable: false)
        click(arrow)
        XCTAssertEqual(toggles.count, 3)
        try body.update(ChatLayerMessageTextPresentation(layout), messageId: 2, selectable: true)
        scene.selectableTextNodeIds = body.selectableTextNodeIds
        node.setExternalSelection(NSRange(location: 1, length: 4))
        scene.clearBubbleSelection()
        click(arrow)
        XCTAssertEqual(toggles.count, 3)
        click(arrow)
        XCTAssertEqual(toggles.count, 4)
    }

    func testRebindingCollapsedExpandedAndPlainRemovesDecorations() throws {
        let text = "First line\nSecond line\nThird line\nFourth line\nLast line"
        let collapsed = source(text, revealed: false)
        let expanded = source(text, revealed: true)
        let body = ChatLayerMessageTextNode(id: "body")
        body.revealBlockAtIndex = { _ in }
        try body.update(ChatLayerMessageTextPresentation(collapsed), messageId: 1, selectable: true)
        let node = body.textNodes[0]
        let layers = try XCTUnwrap(node.layer.sublayers)
        let mask = node.drawingLayer.mask
        XCTAssertEqual(layers.count, 3)
        XCTAssertNotNil(mask)
        XCTAssertFalse(node.drawingLayer.canDrawBlocks)
        XCTAssertEqual(node.drawingLayer.textSize, collapsed.blocks[0].layoutSize)
        XCTAssertLessThan(node.frame.height, node.drawingLayer.textSize.height)
        try body.update(ChatLayerMessageTextPresentation(collapsed), messageId: 1, selectable: true)
        XCTAssertTrue(node.drawingLayer.mask === mask)
        for (a, b) in zip(layers, node.layer.sublayers!) { XCTAssertTrue(a === b) }
        try body.update(ChatLayerMessageTextPresentation(expanded), messageId: 1, selectable: true)
        XCTAssertNil(node.drawingLayer.mask)
        XCTAssertEqual(node.frame.height, node.drawingLayer.textSize.height)
        XCTAssertTrue(body.textNodes[0] === node)
        let plain = MessageTextTests().layout(["plain"])
        try body.update(ChatLayerMessageTextPresentation(plain), messageId: 1, selectable: true)
        XCTAssertEqual(node.layer.sublayers?.count, 1)
        XCTAssertNil(node.layer.mask)
        XCTAssertNil(node.onTextClick)
        XCTAssertTrue(node.drawingLayer.canDrawBlocks)
        XCTAssertEqual(node.drawingLayer.textSize, plain.blocks[0].layoutSize)
        body.revealBlockAtIndex = nil
        XCTAssertFalse(try body.update(ChatLayerMessageTextPresentation(collapsed), messageId: 1, selectable: true))
        XCTAssertTrue(body.children.isEmpty)
    }

    func testCollapsedBlockOffsetsAndToggleIndex() throws {
        let first = source("first\nsecond\nthird\nfourth", revealed: false)
        let last = source("last\nsecond\nthird\nfourth", revealed: true)
        let plain = MessageTextTests().layout(["Between quotes"])
        let layout = FoldingTextLayout(blocks: [first.blocks[0], plain.blocks[0], last.blocks[0]])
        let scene = ChatLayerSceneView(frame: NSRect(x: 0, y: 0, width: 400, height: 400))
        let body = ChatLayerMessageTextNode(id: "body")
        var toggled: [Int] = []
        body.revealBlockAtIndex = { toggled.append($0) }
        try body.update(ChatLayerMessageTextPresentation(layout), messageId: 1, selectable: true)
        try scene.root.setChildren([body])
        scene.layout()
        XCTAssertEqual(body.textNodes[1].frame.minY, first.size.height)
        XCTAssertEqual(body.textNodes[2].frame.minY, first.size.height + plain.size.height)
        for index in [0, 2] {
            let frame = body.textNodes[index].frame
            let point = NSPoint(x: frame.maxX - 8, y: frame.maxY - 9)
            scene.handlePointer(.down, at: point)
            scene.handlePointer(.up, at: point)
        }
        XCTAssertEqual(toggled, [0, 2])
        body.textNodes[1].setSelection(NSRange(location: 0, length: 4))
        let frame = body.textNodes[2].frame
        let point = NSPoint(x: frame.maxX - 8, y: frame.maxY - 9)
        scene.handlePointer(.down, at: point)
        scene.handlePointer(.up, at: point)
        XCTAssertEqual(toggled, [0, 2])
    }

    func testFoldKeyboardAndAccessibilityActions() throws {
        TGUIKitAccessibility.isEnabled = true
        let layout = source("First\nSecond\nThird\nFourth", revealed: false)
        let scene = ChatLayerSceneView(frame: NSRect(x: 0, y: 0, width: 300, height: 300))
        let body = ChatLayerMessageTextNode(id: "body")
        var toggles = 0
        body.revealBlockAtIndex = { _ in toggles += 1 }
        try body.update(ChatLayerMessageTextPresentation(layout), messageId: 1, selectable: false)
        try scene.root.setChildren([body])
        let node = body.textNodes[0]
        XCTAssertTrue(node.acceptsKeyboardFocus)
        let element = try XCTUnwrap(scene.accessibilityChildren()?.first as? NSAccessibilityProtocol)
        XCTAssertTrue(element.accessibilityPerformPress())
        XCTAssertEqual(toggles, 1)
        for code in [UInt16(36), 49] {
            let event = try XCTUnwrap(NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0, windowNumber: 0, context: nil, characters: "", charactersIgnoringModifiers: "", isARepeat: false, keyCode: code))
            XCTAssertTrue(node.onKeyDown?(event) == true)
        }
        XCTAssertEqual(toggles, 3)
        node.isEnabled = false
        XCTAssertFalse(element.accessibilityPerformPress())
        XCTAssertEqual(toggles, 3)
        node.isEnabled = true
        node.setSelection(NSRange(location: 0, length: 3))
        XCTAssertFalse(element.accessibilityPerformPress())
        let plain = MessageTextTests().layout(["plain"])
        try body.update(ChatLayerMessageTextPresentation(plain), messageId: 1, selectable: false)
        XCTAssertFalse(node.acceptsKeyboardFocus)
        XCTAssertNil(node.onAccessibilityPress)
    }

    func testSelectedFoldedAndExpandedPixels() throws {
        for scale in [CGFloat(1), 2, 3] {
            System.updateScaleFactor(scale)
            for revealed in [false, true] {
                for code in [false, true] {
                    let layout = source("First quoted line\nSecond quoted line\nThird line\nFourth line", revealed: revealed, code: code)
                    layout.blocks[0].text.selectedRange.range = NSRange(location: 2, length: 28)
                    let frame = NSRect(origin: .zero, size: layout.size)
                    let scene = ChatLayerSceneView(frame: frame)
                    scene.backgroundColor = .clear
                    let body = ChatLayerMessageTextNode(id: "body")
                    body.revealBlockAtIndex = { _ in }
                    try body.update(ChatLayerMessageTextPresentation(layout), messageId: 1, selectable: true)
                    try scene.root.setChildren([body])
                    let native = makeReferenceFoldingWrapper(layout.blocks[0])
                    XCTAssertEqual(ViewSnapshot.render(native, scale: scale).differingPixels(from: ViewSnapshot.render(scene, scale: scale), tolerance: 0), 0)
                }
            }
        }
    }

}
