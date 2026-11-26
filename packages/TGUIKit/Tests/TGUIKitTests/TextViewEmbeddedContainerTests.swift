import Cocoa
import XCTest
@testable import TGUIKit

private final class EmbeddedScaleWindow: NSWindow {
    var scale: CGFloat = 2
    override var backingScaleFactor: CGFloat { scale }
}

final class TextViewEmbeddedContainerTests: XCTestCase {
    override func setUp() { TGUIKitTestBootstrap.install() }

    func layout(spoiler: Bool = false) -> TextViewLayout {
        let text = NSMutableAttributedString(string: "Message link مرحبا 👩🏽‍💻\nSecond line", attributes: [.font: NSFont.systemFont(ofSize: 16), .foregroundColor: NSColor.black])
        if spoiler { text.addAttribute(TextInputAttributes.spoiler, value: true, range: NSRange(location: 0, length: 7)) }
        let layout = TextViewLayout(text)
        layout.measure(width: 260)
        return layout
    }

    func mask(_ size: NSSize) -> CALayer {
        let layer = SimpleLayer()
        layer.frame = CGRect(origin: .zero, size: size)
        let context = CGContext(data: nil, width: max(1, Int(size.width)), height: max(1, Int(size.height)), bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.setFillColor(NSColor.white.cgColor)
        context.fill(CGRect(x: 0, y: 0, width: size.width * 0.7, height: size.height))
        layer.contents = context.makeImage()
        layer.contentsGravity = .resize
        return layer
    }

    func fixture(_ variant: Int, eager: Bool) -> TextView {
        let view = TextView()
        if eager { _ = view.embeddedContainer }
        let value = layout(spoiler: variant == 7)
        view.update(value)
        if variant == 8 { value.selectedRange.range = NSRange(location: 0, length: 7); view.update(value) }
        if variant == 1 || variant == 2 {
            let mask = mask(view.bounds.size)
            view.set(mask: mask)
            if variant == 2 { mask.frame = .zero; mask.contents = nil }
        }
        if variant == 3 || variant == 4 {
            view.highlight(text: "Message", color: .yellow)
            if variant == 4 { view.update(value) }
        }
        if variant == 5 || variant == 6 {
            view.blurBackground = .red
            view.update(value)
            if variant == 6 {
                view.lockDrawingLayer = true
                view.blurBackground = nil
                view.update(value)
                view.lockDrawingLayer = false
            }
        }
        if [2, 4, 5, 6, 7].contains(variant) {
            let media = CALayer()
            media.frame = CGRect(x: 2, y: 2, width: 18, height: 18)
            media.backgroundColor = NSColor.blue.cgColor
            view.addEmbeddedLayer(media)
            view.checkEmbeddedUnderSpoiler()
        }
        if variant == 6 { view.update(value) }
        return view
    }

    func testCaptureRendering() throws {
        guard let directory = ProcessInfo.processInfo.environment["TEXT_CONTAINER_CAPTURE_DIRECTORY"] else { throw XCTSkip("Opt-in original/current pixel capture") }
        let root = URL(fileURLWithPath: directory)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        var dimensions: [String: [Int]] = [:]
        for scale in [CGFloat(1), 2, 3] {
            for variant in 0..<9 {
                let pixels = ViewSnapshot.render(fixture(variant, eager: false), scale: scale)
                let name = "\(Int(scale))_\(variant).rgba"
                try Data(pixels.bytes).write(to: root.appendingPathComponent(name))
                dimensions[name] = [pixels.width, pixels.height]
            }
        }
        try JSONSerialization.data(withJSONObject: dimensions, options: [.prettyPrinted, .sortedKeys]).write(to: root.appendingPathComponent("dimensions.json"))
    }

    func testPlainUpdatesAndMasksDoNotCreateTheMediaContainer() {
        let view = TextView()
        XCTAssertEqual(view.layer?.sublayers?.count, 1)
        for _ in 0..<10 {
            view.update(layout())
            view.layoutSubtreeIfNeeded()
            view.set(mask: nil)
            view.checkEmbeddedUnderSpoiler()
        }
        XCTAssertEqual(view.layer?.sublayers?.count, 1)
        view.set(mask: mask(view.bounds.size))
        XCTAssertEqual(view.layer?.sublayers?.count, 1)
        view.set(mask: nil)
        XCTAssertEqual(view.layer?.sublayers?.count, 1)
    }

    func testDeferredMaskKeepsTheSnapshotAndContainerIdentity() throws {
        let view = TextView()
        view.update(layout())
        let scale = System.backingScale
        defer { System.updateScaleFactor(scale) }
        let original = mask(view.bounds.size), frame = original.frame
        let contents = original.contents as AnyObject?
        view.set(mask: original)
        original.frame = .zero; original.contents = nil
        System.updateScaleFactor(scale == 3 ? 1 : 3)
        XCTAssertEqual(view.layer?.sublayers?.count, 1)
        let container = view.embeddedContainer
        let copy = try XCTUnwrap(container.mask)
        XCTAssertFalse(copy === original)
        XCTAssertEqual(copy.frame, frame)
        XCTAssertEqual(copy.contentsScale, scale)
        XCTAssertTrue((copy.contents as AnyObject?) === contents)
        XCTAssertEqual(container.frame, view.bounds)
        XCTAssertTrue(view.embeddedContainer === container)
        view.set(mask: nil)
        XCTAssertNil(container.mask)
        view.update(layout())
        XCTAssertTrue(view.embeddedContainer === container)
    }

    func testLateMediaUsesCurrentWindowScaleAndFollowsChanges() {
        let view = TextView()
        view.update(layout())
        let window = EmbeddedScaleWindow(contentRect: CGRect(x: 0, y: 0, width: 300, height: 100), styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = view
        defer { window.contentView = nil; window.close() }
        window.scale = 3
        view.viewDidChangeBackingProperties()
        XCTAssertEqual(view.layer?.sublayers?.count, 1)
        let container = view.embeddedContainer
        XCTAssertEqual(container.contentsScale, 3)
        window.scale = 1
        view.viewDidChangeBackingProperties()
        XCTAssertEqual(container.contentsScale, 1)
    }

    func testLateMediaPreservesHighlightAndBlurLayerOrder() throws {
        for variant in [3, 4, 5, 6] {
            let eager = fixture(variant, eager: true), lazy = fixture(variant, eager: false)
            let container = lazy.embeddedContainer
            let expected = eager.embeddedContainer
            XCTAssertEqual(container.superlayer === lazy.layer, expected.superlayer === eager.layer)
            let actualLayers = try XCTUnwrap(container.superlayer?.sublayers)
            let expectedLayers = try XCTUnwrap(expected.superlayer?.sublayers)
            XCTAssertEqual(actualLayers.firstIndex { $0 === container }, expectedLayers.firstIndex { $0 === expected })
            XCTAssertEqual(actualLayers.firstIndex { $0 === lazy.drawingLayer }, expectedLayers.firstIndex { $0 === eager.drawingLayer })
        }
    }

    func testLateContainerPixelsMatchEagerContainers() {
        for scale in [CGFloat(1), 2, 3] {
            for variant in 0..<9 {
                let actual = ViewSnapshot.render(fixture(variant, eager: false), scale: scale)
                let expected = ViewSnapshot.render(fixture(variant, eager: true), scale: scale)
                XCTAssertEqual(actual.differingPixels(from: expected, tolerance: 0), 0, "scale=\(scale), variant=\(variant)")
            }
        }
    }
}
