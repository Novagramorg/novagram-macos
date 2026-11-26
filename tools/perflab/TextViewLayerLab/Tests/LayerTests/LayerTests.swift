import Cocoa
import XCTest
@testable import TGUIKit
@testable import ChatTextRows

private var icons: [NSImage] = []
final class LayerTests: XCTestCase {
    override func setUp() {
        _ = NSApplication.shared
        NSApp.setActivationPolicy(.accessory)
        System.updateScaleFactor(2)
        if icons.isEmpty {
            for name in ["Icon_SearchField", "Icon_SearchClear", "Icon_Quote", "Icon_Quote_Collapse", "Icon_Quote_Expand", "Icon_CopyCode"] {
                let image = NSImage(size: NSSize(width: 16, height: 16), flipped: false) { rect in
                    NSColor.black.setFill(); rect.insetBy(dx: 3, dy: 3).fill(); return true
                }
                image.setName(name)
                icons.append(image)
            }
        }
    }
    override func tearDown() { System.updateScaleFactor(2) }

    func layout(_ kind: Int, width: CGFloat = 220, alignment: NSTextAlignment = .left) -> TextViewLayout {
        let texts = ["12:34", "A name and a second line\nMore text", "مرحبا English שלום", "中文 日本語 한글 café ffi", "👩🏽‍💻 👨‍👩‍👧‍👦 🦆 🇦🇪", "underlined text and styled words", "a strikethrough sample", "red and blue mixed fonts", "hidden text and visible text", "A quote spanning multiple lines with a link", "let answer = 42\nprint(answer)", "", "A very long message that gets truncated at the constrained width", "an embedded emoji placeholder"]
        let text = texts[kind % texts.count]
        let value = NSMutableAttributedString(string: text, attributes: [.font: NSFont.systemFont(ofSize: 14), .foregroundColor: NSColor.black])
        let range = NSRange(location: 0, length: min(8, value.length))
        if range.length > 0 {
            switch kind % texts.count {
            case 5: value.addAttribute(.underlineStyle, value: 1, range: range)
            case 6: value.addAttribute(.strikethroughStyle, value: 1, range: range)
            case 7: value.addAttributes([.foregroundColor: NSColor.red, .font: NSFont.boldSystemFont(ofSize: 18)], range: range)
            case 8: value.addAttribute(TextInputAttributes.spoiler, value: true, range: range)
            case 9, 10:
                let header = kind == 10 ? TextNode.layoutText(NSAttributedString(string: "Swift", attributes: [.font: NSFont.systemFont(ofSize: 12), .foregroundColor: NSColor.blue]), nil, 1, .end, NSSize(width: 200, height: 20), nil, false, .left) : nil
                let data = TextViewBlockQuoteData(id: 1, colors: .init(main: .blue, secondary: .red, tertiary: .green), isCode: kind == 10, header: header)
                value.addAttribute(TextInputAttributes.quote, value: data, range: NSRange(location: 0, length: value.length))
            case 13: value.addAttribute(TextInputAttributes.embedded, value: "emoji", range: range)
            default: break
            }
        }
        let layout = TextViewLayout(value, maximumNumberOfLines: 4, cutout: kind % 2 == 0 ? TextViewCutout(topLeft: NSSize(width: 14, height: 20)) : nil, alignment: alignment)
        layout.measure(width: width)
        return layout
    }

    func pixels(scale: CGFloat, _ draw: (CGContext) -> Void) -> Data {
        let ctx = CGContext(data: nil, width: 1200, height: 480, bitsPerComponent: 8, bytesPerRow: 4800, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.scaleBy(x: scale, y: scale)
        ctx.translateBy(x: 8, y: 8)
        draw(ctx)
        return Data(bytes: ctx.data!, count: 2304000)
    }

    func testExistingViewPixelsAgainstPreviousRenderer() {
        let old = LegacyTextRenderer(), new = TextView()
        for scale in [CGFloat(1), 2, 3] {
            System.updateScaleFactor(scale)
            for kind in 0..<14 {
                for alignment in [NSTextAlignment.left, .center, .right] {
                    for width in [CGFloat(95), 300] {
                        for selected in [false, true] {
                            let a = layout(kind, width: width, alignment: alignment), b = layout(kind, width: width, alignment: alignment)
                            for text in [a, b] where selected && text.attributedString.length > 0 {
                                text.selectedRange = TextSelectedRange(range: NSRange(location: 0, length: min(4, text.attributedString.length)), color: .yellow)
                                text.additionalSelections = [TextSelectedRange(range: NSRange(location: 0, length: min(2, text.attributedString.length)), color: .green)]
                            }
                            old.update(nil); new.update(nil)
                            old.update(a); new.update(b)
                            old.setFrameSize(NSSize(width: width, height: a.layoutSize.height + 6))
                            new.setFrameSize(old.frame.size)
                            old.layout(); new.layout()
                            let before = pixels(scale: scale) { old.draw(old.drawingLayer, in: $0) }
                            let after = pixels(scale: scale) { new.draw(new.drawingLayer, in: $0) }
                            XCTAssertEqual(before, after, "kind=\(kind), scale=\(scale), width=\(width), selected=\(selected)")
                            if kind != 11 { XCTAssertTrue(before.contains { $0 != 0 }) }
                        }
                    }
                }
            }
        }
    }

    func testStandaloneLayerPixelsAndMutableLayoutUpdates() {
        let old = LegacyTextRenderer(), layer = TextViewLayer()
        old.disableBackgroundDrawing = true
        old.isSelectable = false
        for scale in [CGFloat(1), 2, 3] {
            System.updateScaleFactor(scale)
            layer.contentsScale = scale
            for kind in 0..<14 {
                for alignment in [NSTextAlignment.left, .center, .right] {
                    let text = layout(kind, width: 240, alignment: alignment)
                    for limit in [Int?.none, 0, 2, 10000] {
                        text.maxGlyphDrawCount = limit
                        old.update(text)
                        old.setFrameSize(NSSize(width: 260, height: text.layoutSize.height + 6))
                        old.layout()
                        layer.bounds = old.drawingLayer.bounds
                        layer.update(text, size: old.frame.size)
                        let before = pixels(scale: scale) { old.draw(old.drawingLayer, in: $0) }
                        let after = pixels(scale: scale) { layer.draw(in: $0) }
                        XCTAssertEqual(before, after, "kind=\(kind), scale=\(scale), limit=\(String(describing: limit))")
                    }
                }
            }
        }
    }

    func testTimestampMigrationPixelsAndGeometry() {
        let old = LegacyChatTextLayer(), new = CurrentChatTextLayer()
        for scale in [CGFloat(1), 2, 3] {
            System.updateScaleFactor(scale)
            old.updateScale(scale); new.updateScale(scale)
            for i in 0..<100 {
                let text = layout(i % 8, width: CGFloat(80 + i % 200), alignment: [.left, .center, .right][i % 3])
                old.update(text); new.update(text)
                for size in [text.layoutSize, NSSize(width: text.layoutSize.width + 15.5, height: text.layoutSize.height + 3)] {
                    old.bounds.size = size; new.bounds.size = size
                    old.updateDrawLayer(); new.updateDrawLayer()
                    let a = old.sublayers![0], b = new.sublayers![0]
                    XCTAssertEqual(a.frame, b.frame)
                    XCTAssertEqual(a.bounds, b.bounds)
                    XCTAssertEqual(a.contentsScale, b.contentsScale)
                    XCTAssertEqual(pixels(scale: scale) { a.draw(in: $0) }, pixels(scale: scale) { b.draw(in: $0) })
                }
            }
        }
    }

    func testLayerDoesNotMutateSelectionOrRetainReplacedLayouts() {
        let layer = TextViewLayer()
        weak var released: TextViewLayout?
        autoreleasepool {
            let first = layout(0)
            first.selectedRange = TextSelectedRange(range: NSRange(location: 1, length: 2), color: .yellow)
            layer.update(first)
            released = first
            _ = pixels(scale: 2) { layer.draw(in: $0) }
            XCTAssertEqual(first.selectedRange.range, NSRange(location: 1, length: 2))
        }
        layer.update(layout(1))
        XCTAssertNil(released)
        layer.update(nil)
        XCTAssertNil(layer.textLayout)
        XCTAssertEqual(layer.textSize, .zero)
        XCTAssertFalse(pixels(scale: 2) { layer.draw(in: $0) }.contains { $0 != 0 })
    }

    func testLayerCopyAndInvalidation() {
        let layer = TextViewLayer()
        let text = layout(7)
        layer.update(text, size: NSSize(width: 250, height: 40))
        layer.canDrawBlocks = false
        let copy = TextViewLayer(layer: layer)
        XCTAssertEqual(copy.contentsScale, layer.contentsScale)
        XCTAssertTrue(copy.textLayout === text)
        XCTAssertEqual(copy.textSize, layer.textSize)
        XCTAssertFalse(copy.canDrawBlocks)
        XCTAssertEqual(pixels(scale: 2) { layer.draw(in: $0) }, pixels(scale: 2) { copy.draw(in: $0) })
        layer.display()
        layer.update(text)
        XCTAssertTrue(layer.needsDisplay())
    }
}

extension LayerTests {
    func testSpoilerAnimationFlagsBlocksAndBlurredBackgrounds() {
        let old = LegacyTextRenderer(), new = TextView()
        for kind in [8, 9, 10] {
            for clear in [false, true] {
                for animating in [false, true] {
                    for blocks in [false, true] {
                        for blur in [false, true] {
                            old.update(nil); new.update(nil)
                            old.update(layout(kind)); new.update(layout(kind))
                            old.clearExceptRevealed = clear
                            old.inAnimation = animating
                            new.labSetDrawFlags(revealed: clear, animating: animating)
                            for view in [old as TextView, new] {
                                view.canDrawBlocks = blocks
                                view.blurBackground = blur ? NSColor.gray.withAlphaComponent(0.3) : nil
                                view.layout()
                            }
                            XCTAssertEqual(pixels(scale: 2) { old.draw(old.drawingLayer, in: $0) }, pixels(scale: 2) { new.draw(new.drawingLayer, in: $0) })
                            XCTAssertEqual(old.referenceBlockHeaderRects.map { $0.0 }, new.labHeaderRects.map { $0.0 })
                            XCTAssertEqual(old.referenceBlockHeaderRects.map { $0.1 }, new.labHeaderRects.map { $0.1 })
                        }
                    }
                }
            }
        }
    }
}

private final class RenderWindow: NSWindow {
    var pretendKey = false
    override var isKeyWindow: Bool { pretendKey }
}
private final class DrawCountingView: TextView {
    var draws = 0
    override func draw(_ layer: CALayer, in ctx: CGContext) {
        draws += 1
        super.draw(layer, in: ctx)
    }
}
extension LayerTests {
    func testKeyWindowSelectionAndSubclassDrawing() {
        let window = RenderWindow(contentRect: NSRect(x: 0, y: 0, width: 400, height: 100), styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        defer { window.close() }
        let old = LegacyTextRenderer(), new = DrawCountingView()
        window.contentView!.addSubview(old)
        window.contentView!.addSubview(new)
        for key in [false, true] {
            window.pretendKey = key
            for kind in [0, 2, 9, 10] {
                for view in [old as TextView, new] {
                    let text = layout(kind)
                    text.selectedRange = TextSelectedRange(range: NSRange(location: 0, length: min(4, text.attributedString.length)))
                    view.update(text)
                    view.layout()
                }
                let before = pixels(scale: 2) { old.drawingLayer.draw(in: $0) }
                let count = new.draws
                let after = pixels(scale: 2) { new.drawingLayer.draw(in: $0) }
                XCTAssertEqual(new.draws, count + 1)
                XCTAssertEqual(before, after)
            }
        }
    }

    func testHostedDrawingLayerDoesNotRetainView() {
        weak var released: TextView?
        var drawing: CALayer?
        autoreleasepool {
            let view = TextView()
            view.update(layout(0))
            drawing = view.drawingLayer
            released = view
        }
        XCTAssertNil(released)
        XCTAssertFalse(pixels(scale: 2) { drawing!.draw(in: $0) }.contains { $0 != 0 })
    }

    func testBenchmark() throws {
        guard ProcessInfo.processInfo.environment["TEXT_LAYER_BENCHMARK"] == "1" else { throw XCTSkip("Opt-in release benchmark") }
        let oldView = LegacyTextRenderer(), newView = TextView()
        let plainView = TextView(), layer = TextViewLayer()
        plainView.disableBackgroundDrawing = true
        plainView.isSelectable = false
        plainView.userInteractionEnabled = false
        let oldChat = LegacyChatTextLayer(), newChat = CurrentChatTextLayer()
        let text = layout(0), styled = layout(7)
        oldView.update(styled); newView.update(styled)
        oldChat.update(text); newChat.update(text)
        plainView.update(text)
        layer.update(text)
        layer.bounds = plainView.drawingLayer.bounds
        let ctx = CGContext(data: nil, width: 600, height: 100, bitsPerComponent: 8, bytesPerRow: 2400, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.scaleBy(x: 2, y: 2)
        var checksum: CGFloat = 0
        let count = 2000
        var results: [[String: Any]] = []
        func run(_ scenario: String, candidate: Bool) -> Double {
            let start = CACurrentMediaTime()
            for _ in 0..<count {
                switch scenario {
                case "view_redraw":
                    if candidate { newView.draw(newView.drawingLayer, in: ctx) }
                    else { oldView.draw(oldView.drawingLayer, in: ctx) }
                case "timestamp_redraw":
                    if candidate { newChat.sublayers![0].draw(in: ctx) }
                    else { oldChat.sublayers![0].draw(in: ctx) }
                case "timestamp_bind":
                    if candidate { newChat.update(text); checksum += newChat.bounds.width }
                    else { oldChat.update(text); checksum += oldChat.bounds.width }
                case "decorative_bind_draw":
                    if candidate { layer.update(text); layer.draw(in: ctx) }
                    else { plainView.update(text); plainView.draw(plainView.drawingLayer, in: ctx) }
                default:
                    if candidate {
                        let fresh = TextViewLayer()
                        fresh.update(text)
                        fresh.bounds = CGRect(origin: .zero, size: fresh.textSize).insetBy(dx: -2, dy: -3)
                        checksum += fresh.textSize.width
                    } else {
                        let fresh = TextView()
                        fresh.isSelectable = false
                        fresh.userInteractionEnabled = false
                        fresh.disableBackgroundDrawing = true
                        fresh.update(text)
                        checksum += fresh.frame.width
                    }
                }
            }
            return (CACurrentMediaTime() - start) * 1_000_000 / Double(count)
        }
        for scenario in ["view_redraw", "timestamp_redraw", "timestamp_bind", "decorative_bind_draw", "cold_decorative"] {
            _ = run(scenario, candidate: false); _ = run(scenario, candidate: true)
            var before: [Double] = [], after: [Double] = []
            for iteration in 0..<9 {
                if iteration % 2 == 0 { before.append(run(scenario, candidate: false)); after.append(run(scenario, candidate: true)) }
                else { after.append(run(scenario, candidate: true)); before.append(run(scenario, candidate: false)) }
            }
            results.append(["scenario": scenario, "baseline_us": before.sorted()[4], "candidate_us": after.sorted()[4], "baseline_trials_us": before, "candidate_trials_us": after])
        }
        XCTAssertGreaterThan(checksum, 0)
        let data = try JSONSerialization.data(withJSONObject: ["batches": 9, "iterations_per_batch": count, "results": results], options: [.prettyPrinted, .sortedKeys])
        try data.write(to: URL(fileURLWithPath: "/tmp/text-layer-benchmark.json"))
        print(String(data: data, encoding: .utf8)!)
    }
}

extension LayerTests {
    func testStandaloneBlocksAdditionalSelectionsAndRemeasurement() {
        let old = LegacyTextRenderer(), layer = TextViewLayer()
        old.disableBackgroundDrawing = true
        old.isSelectable = false
        for kind in [0, 8, 9, 10] {
            let text = layout(kind)
            text.selectedRange = TextSelectedRange(range: NSRange(location: 0, length: 2), color: .red)
            text.additionalSelections = [TextSelectedRange(range: NSRange(location: 1, length: 2), color: .green)]
            for width in [CGFloat(95), 220] {
                text.measure(width: width)
                for blocks in [false, true] {
                    old.canDrawBlocks = blocks
                    old.update(text)
                    old.layout()
                    layer.canDrawBlocks = blocks
                    layer.update(text)
                    layer.bounds = old.drawingLayer.bounds
                    XCTAssertEqual(pixels(scale: 2) { old.draw(old.drawingLayer, in: $0) }, pixels(scale: 2) { layer.draw(in: $0) })
                }
            }
        }
    }
}
