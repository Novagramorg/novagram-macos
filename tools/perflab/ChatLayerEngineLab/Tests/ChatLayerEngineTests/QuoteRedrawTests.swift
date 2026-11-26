import Cocoa
import XCTest
import TGUIKit
import InputTextView

final class QuoteRedrawTests: XCTestCase {
    override func setUp() { TGUIKitTestBootstrap.install(); System.updateScaleFactor(2) }
    override func tearDown() { System.updateScaleFactor(2); DeviceGraphicsContextSettings.install(nil) }

    func quotes(code: Bool = false, header: Bool = false, colors: Int = 2) -> [TextViewBlockQuote] {
        return StaticQuoteTests().source("A quoted paragraph\nAnother quoted line", code: code, colors: colors, header: header).blocks[0].text.blockQuotes
    }
    func layer(_ value: [TextViewBlockQuote]) -> FoldingTextQuoteLayer {
        let layer = FoldingTextQuoteLayer()
        layer.frame = CGRect(x: 0, y: 0, width: 260, height: 110)
        layer.blockQuotes = value
        layer.displayIfNeeded()
        XCTAssertNotNil(layer.contents)
        XCTAssertFalse(layer.needsDisplay())
        return layer
    }
    func pixels(_ layer: CALayer) -> PixelBuffer {
        layer.displayIfNeeded()
        let scale = layer.contentsScale
        let context = CGContext(data: nil, width: Int(layer.bounds.width * scale), height: Int(layer.bounds.height * scale), bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.scaleBy(x: scale, y: scale)
        layer.render(in: context)
        return PixelBuffer(context.makeImage()!)
    }
    func testRepeatedAndEquivalentAssignmentsKeepRenderedContents() {
        for code in [false, true] {
            let value = quotes(code: code), layer = layer(value)
            let first = pixels(layer)
            for _ in 0..<20 {
                layer.blockQuotes = value
                XCTAssertFalse(layer.needsDisplay())
                layer.blockQuotes = quotes(code: code)
                XCTAssertFalse(layer.needsDisplay())
                XCTAssertEqual(first, pixels(layer))
            }
            value[0].range.location += 1
            layer.blockQuotes = value
            XCTAssertFalse(layer.needsDisplay())
        }
    }
    func testMutableDrawingInputsInvalidateAndMatchOriginalPixels() {
        let value = quotes(), layer = layer(value), original = OriginalRedrawQuoteLayer()
        original.frame = layer.frame
        original.blockQuotes = value
        XCTAssertEqual(pixels(layer).differingPixels(from: pixels(original), tolerance: 0), 0)
        let changes: [() -> Void] = [
            { value[0].frame.origin.x += 3 },
            { value[0].frame.size.width -= 12 },
            { value[0].frame.size.height += 8 },
            { value[0].colors = .init(main: .red, secondary: .blue, tertiary: .green) },
            { value[0].colors = .init(main: .red, secondary: nil, tertiary: .green) },
            { value[0].colors = .init(main: .red) },
            { value[0].isCode = true },
            { value[0].header = TextNode.layoutText(NSAttributedString(string: "Swift", attributes: [.font: NSFont.systemFont(ofSize: 12), .foregroundColor: NSColor.blue]), nil, 1, .end, NSSize(width: 200, height: 40), nil, false, .left) },
            { value[0].header = nil },
            { value[0].isCode = false }
        ]
        for change in changes {
            change()
            layer.blockQuotes = value; original.blockQuotes = value
            XCTAssertTrue(layer.needsDisplay())
            XCTAssertEqual(pixels(layer).differingPixels(from: pixels(original), tolerance: 0), 0)
        }
    }
    func testArrayChangesRemovalAndReuseMatchOriginalPixels() {
        let first = quotes(), second = quotes(code: true)
        second[0].frame.origin.y += 35
        let layer = layer(first), original = OriginalRedrawQuoteLayer()
        original.frame = layer.frame
        for value in [first + second, second + first, [], second, first] {
            layer.blockQuotes = value; original.blockQuotes = value
            XCTAssertTrue(layer.needsDisplay())
            XCTAssertEqual(pixels(layer).differingPixels(from: pixels(original), tolerance: 0), 0)
            layer.blockQuotes = value
            XCTAssertFalse(layer.needsDisplay())
        }
    }
    func testScaleBoundsAndGraphicsSettingsInvalidate() throws {
        let value = quotes(), layer = layer(value)
        for scale: CGFloat in [1, 3, 2] {
            System.updateScaleFactor(scale)
            layer.blockQuotes = value
            XCTAssertTrue(layer.needsDisplay())
            layer.displayIfNeeded()
            layer.contentsScale = scale
            layer.blockQuotes = value
            XCTAssertTrue(layer.needsDisplay())
            layer.displayIfNeeded()
        }
        layer.bounds.size.width += 5
        layer.blockQuotes = value
        XCTAssertTrue(layer.needsDisplay())
        layer.displayIfNeeded()
        let old = DeviceGraphicsContextSettings.shared
        let context = try XCTUnwrap(CGContext(data: nil, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 32, space: CGColorSpace(name: CGColorSpace.displayP3)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        DeviceGraphicsContextSettings.install(context)
        XCTAssertNotEqual(old, DeviceGraphicsContextSettings.shared)
        layer.blockQuotes = value
        XCTAssertTrue(layer.needsDisplay())
    }
    func testHeadersAndDynamicColorsContinueToRedraw() {
        for value in [quotes(code: true, header: true), quotes()] {
            if value[0].header == nil { value[0].colors = .init(main: .labelColor) }
            let layer = layer(value)
            for _ in 0..<3 {
                layer.blockQuotes = value
                XCTAssertTrue(layer.needsDisplay())
                layer.displayIfNeeded()
            }
        }
    }
    func testExplicitInvalidationClearedContentsAndDirectDrawingStayCorrect() {
        let value = quotes(), layer = layer(value)
        layer.setNeedsDisplay()
        layer.blockQuotes = value
        XCTAssertTrue(layer.needsDisplay())
        layer.displayIfNeeded()
        layer.contents = nil
        layer.blockQuotes = value
        XCTAssertTrue(layer.needsDisplay())
        layer.displayIfNeeded()
        value[0].frame.size.width -= 13
        layer.setNeedsDisplay()
        layer.displayIfNeeded()
        value[0].frame.size.width += 13
        layer.blockQuotes = value
        XCTAssertTrue(layer.needsDisplay())
        layer.displayIfNeeded()
        let fresh = FoldingTextQuoteLayer()
        fresh.frame = layer.frame
        fresh.blockQuotes = value
        let context = CGContext(data: nil, width: 520, height: 220, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        fresh.draw(in: context)
        fresh.blockQuotes = value
        XCTAssertTrue(fresh.needsDisplay())
        XCTAssertEqual(pixels(layer), pixels(fresh))
    }
    func testCachedPixelsMatchOriginalAcrossStylesAndScales() {
        var comparisons = 0
        for scale: CGFloat in [1, 2, 3] {
            System.updateScaleFactor(scale)
            for code in [false, true] {
                for colors in 0...2 {
                    let value = quotes(code: code, colors: colors)
                    let layer = layer(value), original = OriginalRedrawQuoteLayer()
                    original.frame = layer.frame
                    original.blockQuotes = value
                    for _ in 0..<3 {
                        layer.blockQuotes = value; original.blockQuotes = value
                        XCTAssertFalse(layer.needsDisplay())
                        XCTAssertEqual(pixels(layer).differingPixels(from: pixels(original), tolerance: 0), 0)
                        comparisons += 1
                    }
                }
            }
        }
        XCTAssertEqual(comparisons, 54)
    }
    func testAssignmentBeforeGeometryChangesMatchesOriginalPixels() {
        for mode in 0..<3 {
            let value = quotes(), layer = layer(value), original = OriginalRedrawQuoteLayer()
            original.frame = layer.frame
            original.blockQuotes = value
            original.displayIfNeeded()
            layer.blockQuotes = value; original.blockQuotes = value
            for target: CALayer in [layer, original] {
                switch mode {
                case 0: target.frame.size.width += 30
                case 1: target.bounds.origin.x += 4
                default: target.contentsScale = 3
                }
            }
            XCTAssertTrue(layer.needsDisplay())
            XCTAssertEqual(pixels(layer).differingPixels(from: pixels(original), tolerance: 0), 0)
        }
    }

}
