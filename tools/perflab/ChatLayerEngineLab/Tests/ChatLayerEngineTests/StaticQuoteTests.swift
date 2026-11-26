import Cocoa
import XCTest
import TGUIKit
import InputTextView
@testable import ChatLayerEngine

final class StaticQuoteTests: XCTestCase {
    override func setUp() { TGUIKitTestBootstrap.install(); System.updateScaleFactor(2) }
    override func tearDown() { System.updateScaleFactor(2) }

    func source(_ string: String, width: CGFloat = 240, code: Bool = false, colors: Int = 0, collapsable: Bool = false, header: Bool = false) -> FoldingTextLayout {
        let title: (TextNodeLayout, TextNode)? = header ? TextNode.layoutText(NSAttributedString(string: "Swift", attributes: [.font: NSFont.systemFont(ofSize: 12), .foregroundColor: NSColor.blue]), nil, 1, .end, NSSize(width: 200, height: 40), nil, false, .left) : nil
        let quote = TextViewBlockQuoteData(id: 1, colors: .init(main: .blue, secondary: colors > 0 ? .red : nil, tertiary: colors > 1 ? .green : nil), isCode: code, header: title, collapsable: collapsable)
        let text = TextViewLayout(NSAttributedString(string: string, attributes: [.font: NSFont.systemFont(ofSize: 14), .foregroundColor: NSColor.black, TextInputAttributes.quote: quote]))
        text.measure(width: width)
        return FoldingTextLayout(blocks: [.init(text: text)])
    }

    func testStaticQuotePixelsMatchExactNativeWrapper() throws {
        let strings = ["A quoted paragraph that wraps at smaller widths.\nAnother line.", "مرحبا بالعالم English שלום\nالعربية", "中文 日本語 한글\ncafé 👩🏽‍💻 🦆"]
        var comparisons = 0
        for scale in [CGFloat(1), 2, 3] {
            System.updateScaleFactor(scale)
            for width in [CGFloat(190), 420] {
                for (variant, string) in strings.enumerated() {
                    for code in [false, true] {
                        for selected in [false, true] {
                            try autoreleasepool {
                                let source = source(string, width: width, code: code, colors: variant)
                                if selected { source.blocks[0].text.selectedRange.range = NSRange(location: 1, length: 7) }
                                let presentation = ChatLayerMessageTextPresentation(source)
                                XCTAssertTrue(presentation.nativeFeatures.isEmpty)
                                XCTAssertTrue(presentation.blocks[0].clipsTextToBounds)
                                let frame = NSRect(x: 0, y: 0, width: width + 40, height: source.size.height + 40)
                                let native = View(frame: frame)
                                native.backgroundColor = .clear
                                let wrapper = makeReferenceFoldingWrapper(source.blocks[0])
                                wrapper.frame.origin = NSPoint(x: 20, y: 20)
                                native.addSubview(wrapper)
                                let scene = ChatLayerSceneView(frame: frame)
                                scene.backgroundColor = .clear
                                let body = ChatLayerMessageTextNode(id: "body")
                                XCTAssertTrue(try body.update(presentation, messageId: 1, selectable: true))
                                body.frame.origin = NSPoint(x: 20, y: 20)
                                try scene.root.setChildren([body])
                                let before = ViewSnapshot.render(native, scale: scale)
                                let after = ViewSnapshot.render(scene, scale: scale)
                                let differences = before.differingPixels(from: after, tolerance: 0)
                                if differences != 0 {
                                    let base = URL(fileURLWithPath: "/tmp/chat-quote-\(scale)-\(width)-\(variant)-\(code)-\(selected)")
                                    try before.write(to: base.appendingPathExtension("native.png"))
                                    try after.write(to: base.appendingPathExtension("layers.png"))
                                }
                                XCTAssertEqual(differences, 0, "scale=\(scale), width=\(width), variant=\(variant), code=\(code), selected=\(selected)")
                                XCTAssertEqual(viewTreeCount(native), 3)
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

    func testFoldableQuotesRequireCallbackAndCodeHeadersUseLayerInteractions() throws {
        for revealed in [false, true] {
            let value = source("first\nsecond\nthird\nfourth\nfifth", collapsable: true)
            value.blocks = [.init(text: value.blocks[0].text, isRevealed: revealed, size: NSSize(width: 200, height: 30))]
            XCTAssertNotNil(ChatLayerMessageTextPresentation(value).blocks[0].folding)
            XCTAssertFalse(try ChatLayerMessageTextNode(id: "body").update(ChatLayerMessageTextPresentation(value), messageId: 1, selectable: true))
        }
        let code = source("let value = 1", code: true, header: true)
        XCTAssertTrue(ChatLayerMessageTextPresentation(code).nativeFeatures.isEmpty)
        let reflow = source("A collapsible quote that is short at a wide layout but becomes longer than three lines when the available width shrinks.", width: 600, collapsable: true)
        XCTAssertTrue(ChatLayerMessageTextPresentation(reflow).nativeFeatures.isEmpty)
        reflow.blocks[0].text.measure(width: 80)
        XCTAssertNotNil(ChatLayerMessageTextPresentation(reflow).blocks[0].folding)
        reflow.blocks[0].text.measure(width: 600)
        XCTAssertTrue(ChatLayerMessageTextPresentation(reflow).nativeFeatures.isEmpty)
    }

    func testCompleteQuotedRowsMatchNativeAndCanReusePlainRows() throws {
        var comparisons = 0
        for scale in [CGFloat(1), 2, 3] {
            System.updateScaleFactor(scale)
            for width in [CGFloat(320), 620] {
                for variant in [4, 9, 14, 19] {
                    try autoreleasepool {
                        let native = NativePlainRow(PlainRowFixture(width: width, variant: 0))
                        let candidate = LayerPlainRow(PlainRowFixture(width: width, variant: 0))
                        native.bind(PlainRowFixture(width: width, variant: variant, quote: true))
                        candidate.bind(PlainRowFixture(width: width, variant: variant, quote: true))
                        XCTAssertNotNil(candidate.nodes["body"] as? ChatLayerMessageTextNode)
                        XCTAssertEqual(viewTreeCount(native.view), 16)
                        XCTAssertEqual(viewTreeCount(candidate.view), 1)
                        XCTAssertEqual(ViewSnapshot.render(native.view, scale: scale).differingPixels(from: ViewSnapshot.render(candidate.view, scale: scale), tolerance: 0), 0)
                        native.bind(PlainRowFixture(width: width, variant: 0))
                        candidate.bind(PlainRowFixture(width: width, variant: 0))
                        XCTAssertNotNil(candidate.nodes["body"] as? ChatLayerTextNode)
                        XCTAssertEqual(viewTreeCount(native.view), 15)
                        XCTAssertEqual(candidate.view.selectableTextNodeIds, [AnyHashable("body")])
                        comparisons += 1
                    }
                }
            }
        }
        XCTAssertEqual(comparisons, 24)
    }

    func testQuoteClippingIsRemovedWhenNodeIsReusedForPlainText() throws {
        let body = ChatLayerMessageTextNode(id: "body")
        let presentation = ChatLayerMessageTextPresentation(source("quoted"))
        try body.update(presentation, messageId: 1, selectable: true)
        let node = body.textNodes[0]
        XCTAssertTrue(node.clipsChildren)
        XCTAssertNotNil(node.layer.mask)
        let mask = node.layer.mask
        try body.update(presentation, messageId: 1, selectable: true)
        XCTAssertTrue(node.layer.mask === mask)
        let plain = MessageTextTests().layout(["plain"])
        try body.update(ChatLayerMessageTextPresentation(plain), messageId: 2, selectable: true)
        XCTAssertTrue(body.textNodes[0] === node)
        XCTAssertFalse(node.clipsChildren)
        XCTAssertFalse(node.layer.masksToBounds)
        XCTAssertNil(node.layer.mask)
    }

    func testStaticQuoteSelectionGesturesMatchNativeTextView() throws {
        let window = Window(contentRect: NSRect(x: 0, y: 0, width: 600, height: 200), styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        defer { window.contentView = nil; window.close() }
        let root = View(frame: window.contentView!.bounds)
        window.contentView = root
        var comparisons = 0
        for string in ["Quoted words to select\nA second line", "مرحبا English שלום\n中文 日本語"] {
            for clicks in [1, 2, 3] {
                for reverse in [false, true] {
                    let original = source(string), current = source(string)
                    let wrapper = makeReferenceFoldingWrapper(original.blocks[0])
                    let native = try XCTUnwrap(wrapper.subviews.first as? TextView)
                    native.isSelectable = true
                    root.addSubview(wrapper)
                    let scene = ChatLayerSceneView(frame: NSRect(x: 300, y: 0, width: 260, height: 160))
                    root.addSubview(scene)
                    scene.layout()
                    let body = ChatLayerMessageTextNode(id: "body")
                    try body.update(ChatLayerMessageTextPresentation(current), messageId: 1, selectable: true)
                    try scene.root.setChildren([body])
                    let start = NSPoint(x: reverse ? 100 : 12, y: 12)
                    let end = NSPoint(x: reverse ? 12 : 100, y: 12)
                    let down = TextTests().mouse(.leftMouseDown, start, in: native, clicks: clicks)
                    let drag = TextTests().mouse(.leftMouseDragged, end, in: native, clicks: clicks)
                    let up = TextTests().mouse(.leftMouseUp, end, in: native, clicks: clicks)
                    native.mouseDown(with: down)
                    native.mouseDragged(with: drag)
                    native.mouseUp(with: up)
                    let expected = original.blocks[0].text.selectedRange.range
                    scene.handlePointer(.down, at: start, native: down)
                    scene.handlePointer(.dragged, at: end, native: drag)
                    scene.handlePointer(.up, at: end, native: up)
                    XCTAssertEqual(expected, current.blocks[0].text.selectedRange.range)
                    wrapper.removeFromSuperview()
                    scene.removeFromSuperview()
                    comparisons += 1
                }
            }
        }
        XCTAssertEqual(comparisons, 12)
    }
}
